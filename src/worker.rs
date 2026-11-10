use std::collections::HashMap;
use std::sync::mpsc::{Receiver, RecvTimeoutError};
use std::sync::{Arc, Mutex};
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

use crate::config::{self, Settings};
use crate::machine::{Machine, Snapshot};

pub enum Event {
    Apply,
    RestoreAuto,
    Stop,
}

pub struct Shared {
    pub snapshot: Mutex<Snapshot>,
    pub settings: Mutex<Settings>,
}

impl Shared {
    pub fn new(settings: Settings) -> Self {
        Self {
            snapshot: Mutex::new(Snapshot::default()),
            settings: Mutex::new(settings),
        }
    }
}

pub fn spawn(shared: Arc<Shared>, events: Receiver<Event>) -> JoinHandle<()> {
    std::thread::Builder::new()
        .name("smc-worker".into())
        .spawn(move || run(shared, events))
        .expect("failed to spawn SMC worker")
}

fn run(shared: Arc<Shared>, events: Receiver<Event>) {
    let mut machine: Option<Machine> = None;
    let mut last_attempt: Option<Instant> = None;
    let mut last_sensor_refresh: Option<Instant> = None;
    let mut shutting_down = false;

    while !shutting_down {
        let poll = if machine.is_some() {
            Duration::from_millis(1000)
        } else {
            Duration::from_millis(1200)
        };

        match events.recv_timeout(poll) {
            Ok(Event::Stop) | Err(RecvTimeoutError::Disconnected) => {
                shutting_down = true;
                continue;
            }
            Ok(Event::RestoreAuto) => {
                if let Some(m) = machine.as_mut() {
                    m.restore_auto();
                    config::log("restore automatic requested by user");
                }
            }
            Ok(Event::Apply) => {}
            Err(RecvTimeoutError::Timeout) => {}
        }

        if machine.is_none() {
            let ready = last_attempt.map_or(true, |t| t.elapsed() >= Duration::from_secs(3));
            if ready {
                last_attempt = Some(Instant::now());
                match Machine::open() {
                    Ok(m) => {
                        config::log("SMC connected");
                        let snap = m.sample();
                        *shared.snapshot.lock().unwrap() = snap;
                        machine = Some(m);
                    }
                    Err(e) => {
                        let mut snap = Snapshot::default();
                        snap.error = Some(e.to_string());
                        let hint = e.hint();
                        if !hint.is_empty() {
                            snap.error_hint = Some(hint.to_string());
                        }
                        *shared.snapshot.lock().unwrap() = snap;
                    }
                }
            }
        }

        let mut disconnect = false;
        if let Some(m) = machine.as_mut() {
            let refresh = last_sensor_refresh.map_or(true, |t| t.elapsed() >= Duration::from_secs(10));
            if refresh {
                m.refresh_sensors();
                last_sensor_refresh = Some(Instant::now());
            }
            let settings = shared.settings.lock().unwrap().clone();
            let mut snap = m.sample();
            let temps: HashMap<String, f32> = snap
                .temps
                .iter()
                .filter_map(|t| t.value.map(|v| (t.key.clone(), v)))
                .collect();

            match m.apply(&settings, &temps) {
                Ok(actions) => {
                    for a in actions {
                        config::log(&a);
                    }
                }
                Err(e) => {
                    config::log(&format!("apply failed: {e}"));
                    snap.error = Some(e.to_string());
                    let hint = e.hint();
                    if !hint.is_empty() {
                        snap.error_hint = Some(hint.to_string());
                    }
                    // The driver may have gone away; force a reconnect.
                    disconnect = true;
                }
            }

            *shared.snapshot.lock().unwrap() = snap;
        }
        if disconnect {
            machine = None;
        }
    }

    if let Some(m) = machine.as_mut() {
        m.restore_auto();
        config::log("automatic fan control restored on exit");
    }
}
