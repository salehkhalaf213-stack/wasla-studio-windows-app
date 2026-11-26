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

            #[cfg(feature = "portable")]
            {
                println!("QENTRIVO portable build: installer-based updater is disabled.");
            }

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running QENTRIVO");
}
