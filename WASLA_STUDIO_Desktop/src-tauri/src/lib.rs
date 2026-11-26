#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let builder = tauri::Builder::default();

    #[cfg(feature = "updater")]
    let builder = builder.plugin(tauri_plugin_updater::Builder::new().build());

    builder
        .setup(|app| {
            #[cfg(all(not(debug_assertions), feature = "updater"))]
            {
                use tauri_plugin_updater::UpdaterExt;

                let handle = app.handle().clone();
                tauri::async_runtime::spawn(async move {
                    match handle.updater() {
                        Ok(updater) => match updater.check().await {
                            Ok(Some(update)) => {
                                println!("QENTRIVO update {} is available; installing.", update.version);
                                match update.download_and_install(|_, _| {}, || {}).await {
                                    Ok(()) => {
                                        println!("QENTRIVO update installed; restarting.");
                                        handle.restart();
                                    }
                                    Err(error) => {
                                        eprintln!("QENTRIVO updater installation failed: {error}");
                                    }
                                }
                            }
                            Ok(None) => {
                                println!("QENTRIVO is up to date.");
                            }
                            Err(error) => {
                                eprintln!("QENTRIVO update check failed: {error}");
                            }
                        },
                        Err(error) => {
                            eprintln!("QENTRIVO updater initialization failed: {error}");
                        }
                    }
                });
            }

            #[cfg(all(not(debug_assertions), feature = "portable", target_os = "windows"))]
            {
                use std::process::Command;
                use std::os::windows::process::CommandExt;

                match std::env::current_exe() {
                    Ok(executable) => {
                        if let Some(directory) = executable.parent() {
                            let updater_script = directory.join("QENTRIVO-Portable-Updater.ps1");
                            if updater_script.is_file() {
                                let mut command = Command::new("powershell.exe");
                                command
                                    .arg("-NoProfile")
                                    .arg("-NonInteractive")
                                    .arg("-WindowStyle")
                                    .arg("Hidden")
                                    .arg("-ExecutionPolicy")
                                    .arg("Bypass")
                                    .arg("-File")
                                    .arg(updater_script)
                                    .arg("-CurrentVersion")
                                    .arg(env!("CARGO_PKG_VERSION"))
                                    .arg("-ProcessId")
                                    .arg(std::process::id().to_string())
                                    .arg("-AppPath")
                                    .arg(executable)
                                    .creation_flags(0x08000000);

                                if let Err(error) = command.spawn() {
                                    eprintln!("QENTRIVO portable update checker could not start: {error}");
                                }
                            } else {
                                eprintln!("QENTRIVO portable update helper is missing.");
                            }
                        }
                    }
                    Err(error) => {
                        eprintln!("QENTRIVO portable executable path is unavailable: {error}");
                    }
                }
            }

            #[cfg(feature = "portable")]
            {
                println!("QENTRIVO portable build: ZIP-based updater is enabled; installer updater is disabled.");
            }

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running QENTRIVO");
}
