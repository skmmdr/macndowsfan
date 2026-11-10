use std::sync::mpsc::Sender;
use std::sync::Arc;
use std::thread::JoinHandle;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use eframe::egui;

use crate::config::{self, ControlMode, FanSetting, Settings};
use crate::machine::{sensor_curve, FanReading, Snapshot};
use crate::worker::{Event, Shared};

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

const GREEN: egui::Color32 = egui::Color32::from_rgb(88, 200, 130);
const ORANGE: egui::Color32 = egui::Color32::from_rgb(232, 168, 72);
const RED: egui::Color32 = egui::Color32::from_rgb(232, 96, 92);
const MUTED: egui::Color32 = egui::Color32::from_rgb(150, 156, 168);
const ACCENT: egui::Color32 = egui::Color32::from_rgb(120, 170, 255);

pub struct FanApp {
    shared: Arc<Shared>,
    events: Sender<Event>,
    worker: Option<JoinHandle<()>>,
    settings: Settings,
    show_diag: bool,
    last_saved: Option<Instant>,
}

impl FanApp {
    pub fn new(
        cc: &eframe::CreationContext<'_>,
        shared: Arc<Shared>,
        events: Sender<Event>,
        worker: JoinHandle<()>,
    ) -> Self {
        configure_style(&cc.egui_ctx);
        let settings = shared.settings.lock().unwrap().clone();
        Self {
            shared,
            events,
            worker: Some(worker),
            settings,
            show_diag: false,
            last_saved: None,
        }
    }

    fn ensure_fans(&mut self, snap: &Snapshot) {
        if snap.fans.is_empty() {
            return;
        }
        let mut added = false;
        while self.settings.fans.len() < snap.fans.len() {
            let i = self.settings.fans.len();
            let f = &snap.fans[i];
            let rpm = (0.5 * (f.min_rpm + f.max_rpm)).round();
            self.settings.fans.push(FanSetting {
                rpm,
                ..Default::default()
            });
            added = true;
        }
        if added {
            *self.shared.settings.lock().unwrap() = self.settings.clone();
            config::save(&self.settings);
        }
    }

    fn commit(&mut self) {
        *self.shared.settings.lock().unwrap() = self.settings.clone();
        config::save(&self.settings);
        let _ = self.events.send(Event::Apply);
        self.last_saved = Some(Instant::now());
    }
}

impl eframe::App for FanApp {
    fn ui(&mut self, ui: &mut egui::Ui, _frame: &mut eframe::Frame) {
        let snap = self.shared.snapshot.lock().unwrap().clone();
        self.ensure_fans(&snap);
        let before = self.settings.clone();

        egui::Panel::top("header")
            .frame(egui::Frame::NONE.inner_margin(egui::Margin::symmetric(16, 10)))
            .show(ui, |ui| {
                header_ui(ui, &snap);
            });

        let mut restore = false;
        {
            let settings = &mut self.settings;
            let show_diag = &mut self.show_diag;
            let last_saved = self.last_saved;
            egui::Panel::bottom("footer")
                .frame(egui::Frame::NONE.inner_margin(egui::Margin::symmetric(16, 8)))
                .show(ui, |ui| {
                    restore = footer_ui(ui, settings, show_diag, last_saved);
                });
        }

        let show_diag = self.show_diag;
        egui::CentralPanel::default()
            .frame(egui::Frame::NONE.inner_margin(egui::Margin::same(16)))
            .show(ui, |ui| {
                egui::ScrollArea::vertical()
                    .auto_shrink([false, false])
                    .show(ui, |ui| {
                        if let Some(err) = &snap.error {
                            error_ui(ui, err, snap.error_hint.as_deref());
                            ui.add_space(8.0);
                        }
                        fans_ui(ui, &mut self.settings, &snap);
                        ui.add_space(14.0);
                        temps_ui(ui, &snap);
                        if show_diag {
                            ui.add_space(14.0);
                            diagnostics_ui(ui, &snap);
                        }
                    });
            });

        if restore {
            for f in &mut self.settings.fans {
                f.mode = ControlMode::Automatic;
            }
            let _ = self.events.send(Event::RestoreAuto);
        }

        if self.settings != before {
            self.commit();
        }

        ui.ctx().request_repaint_after(Duration::from_millis(250));
    }

    fn on_exit(&mut self, _gl: Option<&eframe::glow::Context>) {
        let _ = self.events.send(Event::Stop);
        if let Some(handle) = self.worker.take() {
            let _ = handle.join();
        }
    }
}

impl Drop for FanApp {
    fn drop(&mut self) {
        let _ = self.events.send(Event::Stop);
        if let Some(handle) = self.worker.take() {
            let _ = handle.join();
        }
    }
}

fn configure_style(ctx: &egui::Context) {
    ctx.set_theme(egui::ThemePreference::Dark);
    ctx.all_styles_mut(|style| {
        style.visuals = egui::Visuals::dark();
        style.visuals.panel_fill = egui::Color32::from_rgb(22, 23, 27);
        style.visuals.window_fill = egui::Color32::from_rgb(28, 30, 35);
        style.visuals.override_text_color = Some(egui::Color32::from_rgb(226, 229, 235));
        style.spacing.item_spacing = egui::vec2(8.0, 6.0);
        style.spacing.button_padding = egui::vec2(10.0, 5.0);
    });
}

fn header_ui(ui: &mut egui::Ui, snap: &Snapshot) {
    ui.horizontal(|ui| {
        ui.label(egui::RichText::new("macndowsfan").size(22.0).strong());
        ui.label(
            egui::RichText::new("Rust edition")
                .size(12.0)
                .color(MUTED),
        );
        ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
            let (color, text) = if snap.error.is_some() {
                (RED, "SMC unavailable")
            } else if snap.fans.is_empty() {
                (ORANGE, "connecting…")
            } else {
                (GREEN, "SMC connected")
            };
            ui.colored_label(color, format!("● {text}"));
            if snap.updated_ms > 0 {
                let age = (now_ms().saturating_sub(snap.updated_ms)) as f32 / 1000.0;
                ui.label(
                    egui::RichText::new(format!("updated {age:.1}s ago"))
                        .size(12.0)
                        .color(MUTED),
                );
            }
        });
    });
}

fn footer_ui(
    ui: &mut egui::Ui,
    settings: &mut Settings,
    show_diag: &mut bool,
    last_saved: Option<Instant>,
) -> bool {
    let mut restore = false;
    ui.horizontal(|ui| {
        let any_forced = settings
            .fans
            .iter()
            .any(|f| f.mode != ControlMode::Automatic);
        if ui
            .add_enabled(any_forced, egui::Button::new("Restore automatic"))
            .clicked()
        {
            restore = true;
        }
        ui.checkbox(show_diag, "Diagnostics");
        ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
            ui.label(
                egui::RichText::new(concat!("v", env!("CARGO_PKG_VERSION")))
                    .size(11.0)
                    .color(MUTED),
            );
            if let Some(t) = last_saved {
                if t.elapsed() < Duration::from_secs(3) {
                    ui.label(egui::RichText::new("Settings saved").size(11.0).color(GREEN));
                }
            }
        });
    });
    restore
}

fn error_ui(ui: &mut egui::Ui, err: &str, hint: Option<&str>) {
    egui::Frame::group(ui.style())
        .fill(egui::Color32::from_rgb(52, 26, 28))
        .show(ui, |ui| {
            ui.label(
                egui::RichText::new("Cannot talk to the SMC")
                    .size(16.0)
                    .strong()
                    .color(RED),
            );
            ui.label(err);
            if let Some(h) = hint {
                ui.label(egui::RichText::new(h).color(ORANGE));
            }
            ui.label(
                egui::RichText::new(
                    "This app talks to \\\\.\\APPLESMC, the signed driver installed by Macs Fan Control. \
                     Macs Fan Control opens it exclusively, so quit it from the tray before retrying.",
                )
                .size(12.0)
                .color(MUTED),
            );
            ui.horizontal(|ui| {
                if ui.button("Retry now").clicked() {
                    ui.ctx().request_repaint();
                }
                if !crate::win::is_elevated() && ui.button("Restart as administrator").clicked() {
                    if crate::win::relaunch_elevated() {
                        ui.ctx().send_viewport_cmd(egui::ViewportCommand::Close);
                    }
                }
                ui.label(
                    egui::RichText::new("The app also retries on its own every few seconds.")
                        .size(11.0)
                        .color(MUTED),
                );
            });
        });
}

fn fans_ui(ui: &mut egui::Ui, settings: &mut Settings, snap: &Snapshot) {
    ui.horizontal(|ui| {
        ui.label(egui::RichText::new("Fans").size(17.0).strong());
        if !snap.fans.is_empty() {
            ui.label(
                egui::RichText::new(format!("{} detected · {}", snap.fans.len(), snap.mode_style))
                    .size(12.0)
                    .color(MUTED),
            );
        }
    });
    ui.add_space(4.0);

    if snap.fans.is_empty() {
        ui.label(egui::RichText::new("No fan data yet.").color(MUTED));
        return;
    }

    for fan in &snap.fans {
        let s = settings.fan(fan.index);
        fan_card(ui, fan, s, snap);
        ui.add_space(8.0);
    }
}

fn fan_card(ui: &mut egui::Ui, fan: &FanReading, s: &mut FanSetting, snap: &Snapshot) {
    let lo = crate::machine::safe_min_rpm(fan.min_rpm);
    let hi = fan.max_rpm.max(lo + 1.0);

    egui::Frame::group(ui.style()).show(ui, |ui| {
        ui.horizontal(|ui| {
            ui.vertical(|ui| {
                ui.label(egui::RichText::new(fan.name.as_str()).size(17.0).strong());
                let pct = if hi > 0.0 { fan.actual / hi } else { 0.0 };
                let color = if !fan.actual.is_finite() {
                    MUTED
                } else if pct > 0.85 {
                    RED
                } else if pct > 0.6 {
                    ORANGE
                } else {
                    GREEN
                };
                let text = if fan.actual.is_finite() {
                    format!("{:.0} RPM", fan.actual)
                } else {
                    "— RPM".to_string()
                };
                ui.label(egui::RichText::new(text).size(28.0).strong().color(color));
            });

            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                egui::ComboBox::from_id_salt(("mode", fan.index))
                    .width(165.0)
                    .selected_text(s.mode.label())
                    .show_ui(ui, |ui| {
                        ui.selectable_value(&mut s.mode, ControlMode::Automatic, "Automatic");
                        ui.selectable_value(&mut s.mode, ControlMode::Constant, "Constant speed");
                        ui.selectable_value(&mut s.mode, ControlMode::Sensor, "Sensor-based");
                    });
                ui.label(egui::RichText::new("Control").size(12.0).color(MUTED));
            });
        });

        if !fan.controllable {
            ui.label(
                egui::RichText::new("This fan exposes no target key (read-only).")
                    .size(12.0)
                    .color(ORANGE),
            );
        }

        ui.add_space(2.0);

        match s.mode {
            ControlMode::Automatic => {
                ui.label(
                    egui::RichText::new("macOS/Boot Camp firmware decides the speed.")
                        .size(12.0)
                        .color(MUTED),
                );
            }
            ControlMode::Constant => {
                ui.add(
                    egui::Slider::new(&mut s.rpm, lo..=hi)
                        .suffix(" RPM")
                        .fixed_decimals(0),
                );
                ui.label(
                    egui::RichText::new(format!(
                        "Min {:.0} · Max {:.0} RPM — clamped to the safe range.",
                        fan.min_rpm, fan.max_rpm
                    ))
                    .size(11.0)
                    .color(MUTED),
                );
            }
            ControlMode::Sensor => {
                ui.horizontal(|ui| {
                    ui.label("Follow sensor:");
                    let now = snap
                        .temps
                        .iter()
                        .find(|t| t.key == s.sensor)
                        .and_then(|t| t.value);
                    let selected = snap
                        .temps
                        .iter()
                        .find(|t| t.key == s.sensor)
                        .map(|t| format!("{} ({})", t.label, t.key))
                        .unwrap_or_else(|| s.sensor.clone());
                    egui::ComboBox::from_id_salt(("sensor", fan.index))
                        .width(230.0)
                        .selected_text(selected)
                        .show_ui(ui, |ui| {
                            for t in &snap.temps {
                                let label = match t.value {
                                    Some(v) => format!(
                                        "{} ({}) — {:.0}°C",
                                        t.label,
                                        t.key,
                                        v
                                    ),
                                    None => format!("{} ({})", t.label, t.key),
                                };
                                ui.selectable_value(&mut s.sensor, t.key.clone(), label);
                            }
                        });
                    if let Some(v) = now {
                        ui.label(
                            egui::RichText::new(format!("now {v:.0}°C"))
                                .size(12.0)
                                .color(MUTED),
                        );
                    }
                });

                ui.horizontal(|ui| {
                    ui.label("Start at");
                    ui.add(
                        egui::Slider::new(&mut s.start_temp, 30.0..=95.0)
                            .suffix(" °C")
                            .fixed_decimals(0),
                    );
                    ui.label("full speed at");
                    ui.add(
                        egui::Slider::new(&mut s.max_temp, s.start_temp + 1.0..=105.0)
                            .suffix(" °C")
                            .fixed_decimals(0),
                    );
                });

                let temp = snap
                    .temps
                    .iter()
                    .find(|t| t.key == s.sensor)
                    .and_then(|t| t.value);
                let target = sensor_curve(
                    temp.unwrap_or(f32::NAN),
                    s.start_temp,
                    s.max_temp,
                    crate::machine::safe_min_rpm(fan.min_rpm),
                    fan.max_rpm,
                );
                ui.label(
                    egui::RichText::new(format!("Computed target: {:.0} RPM", target))
                        .size(12.0)
                        .color(ACCENT),
                );
            }
        }

        ui.horizontal_wrapped(|ui| {
            ui.label(
                egui::RichText::new(format!(
                    "Range {:.0}–{:.0} RPM · type {} · mode key {}",
                    fan.min_rpm, fan.max_rpm, fan.value_type, fan.mode_key
                ))
                .size(11.0)
                .color(MUTED),
            );
            if let Some(t) = fan.target {
                ui.label(
                    egui::RichText::new(format!("target {t:.0} RPM"))
                        .size(11.0)
                        .color(MUTED),
                );
            }
            if fan.forced && s.mode == ControlMode::Automatic {
                ui.label(
                    egui::RichText::new("currently forced by another program")
                        .size(11.0)
                        .color(ORANGE),
                );
            }
        });
    });
}

fn temps_ui(ui: &mut egui::Ui, snap: &Snapshot) {
    ui.horizontal(|ui| {
        ui.label(egui::RichText::new("Temperatures").size(17.0).strong());
        ui.label(
            egui::RichText::new(format!("{} sensors", snap.temps.len()))
                .size(12.0)
                .color(MUTED),
        );
    });
    ui.add_space(4.0);

    if snap.temps.is_empty() {
        ui.label(egui::RichText::new("No temperature sensors found.").color(MUTED));
        return;
    }

    egui::Frame::group(ui.style()).show(ui, |ui| {
        egui::Grid::new("temps_grid")
            .num_columns(4)
            .spacing([26.0, 5.0])
            .striped(true)
            .show(ui, |ui| {
                for (i, t) in snap.temps.iter().enumerate() {
                    ui.label(
                        egui::RichText::new(format!("{} ({})", t.label, t.key))
                            .size(12.0)
                            .color(MUTED),
                    );
                    match t.value {
                        Some(v) => {
                            let color = if v >= 80.0 {
                                RED
                            } else if v >= 65.0 {
                                ORANGE
                            } else {
                                GREEN
                            };
                            ui.label(
                                egui::RichText::new(format!("{v:.1} °C"))
                                    .size(13.0)
                                    .strong()
                                    .color(color),
                            );
                        }
                        None => {
                            ui.label(egui::RichText::new("—").size(13.0).color(MUTED));
                        }
                    }
                    if i % 2 == 1 {
                        ui.end_row();
                    }
                }
            });
    });
}

fn diagnostics_ui(ui: &mut egui::Ui, snap: &Snapshot) {
    egui::CollapsingHeader::new("Diagnostics")
        .default_open(true)
        .show(ui, |ui| {
            if let Some(c) = snap.key_count {
                ui.label(format!("SMC key count: {c}"));
            }
            ui.label(format!("Mode style: {}", snap.mode_style));
            for f in &snap.fans {
                ui.label(format!(
                    "Fan {} · {} · {} · mode key {} · range {:.0}–{:.0} RPM",
                    f.index + 1,
                    f.name,
                    f.value_type,
                    f.mode_key,
                    f.min_rpm,
                    f.max_rpm
                ));
            }
            ui.separator();
            egui::Grid::new("diag_temps")
                .num_columns(3)
                .spacing([18.0, 3.0])
                .show(ui, |ui| {
                    for t in &snap.temps {
                        ui.label(t.key.as_str());
                        ui.label(t.label.as_str());
                        ui.label(match t.value {
                            Some(v) => format!("{v:.2} °C"),
                            None => "read failed".to_string(),
                        });
                        ui.end_row();
                    }
                });
        });
}
