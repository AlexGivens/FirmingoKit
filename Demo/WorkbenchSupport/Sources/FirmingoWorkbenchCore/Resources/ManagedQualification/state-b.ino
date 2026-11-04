// FMS2 qualification: initialized state, zeroed BSS and bounded binary replies.
volatile uint32_t counter = 23;
volatile uint32_t loops;
uint32_t initialData;
uint32_t initialBSS;
uint32_t mode;
uint32_t echoed;
void word(uint8_t *out, uint32_t value) {
  for (uint32_t i = 0; i < 4; ++i) out[i] = uint8_t(value >> (i * 8));
}
void setup() {
  initialData = counter; initialBSS = loops;
  pinMode(6, OUTPUT); digitalWrite(6, 1);
}
void loop() {
  ++counter; ++loops;
  if (Serial.availableForWrite() >= 24) {
    int c = Serial.read();
    if (c >= 0) {
      if (mode == 1) {
        uint8_t reply[24];
        reply[0] = 'F'; reply[1] = 'Q'; reply[2] = '2'; reply[3] = 66;
        word(reply + 4, uint32_t(c)); word(reply + 8, initialData);
        word(reply + 12, initialBSS); word(reply + 16, counter); word(reply + 20, loops);
        Serial.write(reply, 24); mode = 0;
      } else if (mode == 2) {
        Serial.write(uint8_t(c));
        ++echoed; if (echoed == 256) mode = 0;
      } else if (c == 1) { mode = 1; }
      else if (c == 2) { mode = 2; echoed = 0; }
    }
  }
  delay(1);
}
