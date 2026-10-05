#pragma once
// Independently authored facade for the pinned Firmingo stateless ABI, not a full Arduino core.
// Compiler predefined types keep this experimental recipe independent of a conventional sysroot.
/// Compiler-defined unsigned eight-bit integer, independent of libc headers.
using uint8_t = __UINT8_TYPE__;
/// Compiler-defined unsigned sixteen-bit integer used by the resident table header.
using uint16_t = __UINT16_TYPE__;
/// Compiler-defined unsigned thirty-two-bit integer for the ARM resident ABI.
using uint32_t = __UINT32_TYPE__;
/// Compiler-defined signed thirty-two-bit console result type.
using int32_t = __INT32_TYPE__;
/// Compiler-defined native size type, asserted to match the 32-bit target by the table layout.
using size_t = __SIZE_TYPE__;
/// Arduino-style byte alias within the constrained facade.
using byte = uint8_t;
#ifndef FIRMINGO_API_ADDRESS
#error "An exact resident API binding is required"
#endif

/// Exact 32-bit resident table layout from ABI one; the resident owns all mutable state.
struct FirmingoSDKApi {
  /// Resident FAPI magic field; this facade does not authenticate its contents.
  uint32_t magic;
  /// ABI version supplied by the resident.
  uint16_t version;
  /// Complete resident table byte count.
  uint16_t size;
  /// Table offset eight: resident pin configuration.
  void (*pinMode)(uint32_t, uint32_t);
  /// Table offset twelve: resident digital write.
  void (*digitalWrite)(uint32_t, uint32_t);
  /// Table offset sixteen: resident monotonic millisecond clock.
  uint32_t (*millis)();
  /// Table offset twenty: resident bounded-call delay.
  void (*delay)(uint32_t);
  /// Table offset twenty-four: resident byte write.
  uint32_t (*write)(const uint8_t *, uint32_t);
  /// Table offset twenty-eight: resident write capacity.
  uint32_t (*writeAvailable)();
  /// Table offset thirty-two: resident byte read or empty sentinel.
  int32_t (*read)();
  /// Table offset thirty-six: resident readable byte count.
  uint32_t (*available)();
};
static_assert(sizeof(FirmingoSDKApi) == 40, "Require the 32-bit Firmingo API layout");
static_assert(__builtin_offsetof(FirmingoSDKApi, pinMode) == 8, "Require ABI-one table offsets");
static_assert(__builtin_offsetof(FirmingoSDKApi, available) == 36, "Require ABI-one table offsets");
/// Selects only the host-verified resident table address, never a sample hardcoded address.
inline const FirmingoSDKApi &firmingoSDKApi() {
  return *reinterpret_cast<const FirmingoSDKApi *>(FIRMINGO_API_ADDRESS);
}
/// Nano LED pin selected by the pinned experiment, not an RP2040-family default.
constexpr uint32_t LED_BUILTIN = 6;
/// ABI-one pin output mode.
constexpr uint32_t OUTPUT = 1;
/// ABI-one digital high value.
constexpr uint32_t HIGH = 1;
/// ABI-one digital low value.
constexpr uint32_t LOW = 0;
/// Dispatches pin configuration to the resident.
inline void pinMode(uint32_t pin, uint32_t mode) { firmingoSDKApi().pinMode(pin, mode); }
/// Dispatches a digital write to the resident.
inline void digitalWrite(uint32_t pin, uint32_t value) { firmingoSDKApi().digitalWrite(pin, value); }
/// Reads the resident millisecond clock.
inline uint32_t millis() { return firmingoSDKApi().millis(); }
/// Requests a resident delay; bounded execution remains the sketch author's responsibility.
inline void delay(uint32_t value) { firmingoSDKApi().delay(value); }
/// Stateless temporary serial facade; no UART/USB or module-global queue is created.
class FirmingoSDKSerial {
 public:
  /// Network console compatibility call; it does not configure hardware baud.
  void begin(unsigned long) const {}
  /// Reports resident-service availability, not connected-peer readiness.
  explicit operator bool() const { return true; }
  /// Reports readable resident console bytes.
  int available() const { return int(firmingoSDKApi().available()); }
  /// Reports bounded resident write capacity.
  int availableForWrite() const { return int(firmingoSDKApi().writeAvailable()); }
  /// Reads a byte or resident empty sentinel.
  int read() const { return int(firmingoSDKApi().read()); }
  /// Writes one stack-local byte through the resident.
  size_t write(uint8_t value) const { return firmingoSDKApi().write(&value, 1); }
  /// Writes a caller-provided byte range; host/runtime qualification is separate.
  size_t write(const uint8_t *data, size_t count) const { return firmingoSDKApi().write(data, uint32_t(count)); }
  /// Writes a terminated string without linking a libc string implementation.
  size_t print(const char *text) const {
    size_t length = 0;
    while (text[length] != '\0') { ++length; }
    return write(reinterpret_cast<const uint8_t *>(text), length);
  }
  /// Writes text followed by the pinned CRLF convention using temporary stack storage.
  size_t println(const char *text) const {
    const uint8_t ending[] = {13, 10};
    return print(text) + write(ending, 2);
  }
};
/// Temporary facade expression avoids module-global initialization or mutable state.
#define Serial FirmingoSDKSerial()
