/// Source-defined setup entry; forward declaration is required for separate compilation.
void setup();
/// Source-defined loop entry; each invocation must return within firmware constraints.
void loop();
/// Retained globally named Thumb wrapper required by the capsule contract.
extern "C" __attribute__((used, section(".firmingo_entry.setup")))
void firmingo_sketch_setup() { setup(); }
/// Retained loop wrapper, distinct from setup and validated after linking.
extern "C" __attribute__((used, section(".firmingo_entry.loop")))
void firmingo_sketch_loop() { loop(); }
