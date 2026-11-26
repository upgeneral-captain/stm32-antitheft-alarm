#ifndef SETTINGS_H
#define SETTINGS_H
#include <stdint.h>
uint8_t Settings_Load(void);
uint8_t Settings_Save(uint8_t armed);
uint32_t Settings_BootId(void);
#endif
