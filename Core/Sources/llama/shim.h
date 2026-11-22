// Development-only shim: exposes the llama.cpp C API as the `llama` module on Linux/macOS,
// matching the module name of the official llama.xcframework used by the iOS app.
#include <llama.h>
