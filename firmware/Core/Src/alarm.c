#include "alarm.h"
#include "config.h"
static AlarmLevel level;
static uint32_t epoch, single_at;
static uint8_t single, notify_latched;
void Alarm_Init(void) {level=ALARM_LEVEL_NONE;single=notify_latched=0;BUZZER_OFF();LED_R_OFF();}
void Alarm_Stop(void) {Alarm_Init();}
AlarmLevel Alarm_GetLevel(void) {return level;}
void Alarm_BeepOnce(void) {single=1;single_at=HAL_GetTick();BUZZER_ON();}
void Alarm_SetLevel(AlarmLevel next) {
    if(next==level) return;
    if(next==ALARM_LEVEL_NONE && level==ALARM_LEVEL_NOTIFY && notify_latched) return;
    level=next;epoch=HAL_GetTick();
    notify_latched=(next==ALARM_LEVEL_NOTIFY);
    if(next==ALARM_LEVEL_FULL) {single=0;BUZZER_ON();LED_R_ON();}
    else if(next==ALARM_LEVEL_NOTIFY) BUZZER_ON();
    else {BUZZER_OFF();LED_R_OFF();}
}
void Alarm_Tick(void) {
    uint32_t now=HAL_GetTick();
    if(single) {
        if(now-single_at<NOTIFY_BEEP_ON_MS) return;
        single=0;BUZZER_OFF();
    }
    uint32_t elapsed=now-epoch;
    if(level==ALARM_LEVEL_FULL) {
        if(elapsed%(ALARM_BEEP_ON_MS+ALARM_BEEP_OFF_MS)<ALARM_BEEP_ON_MS) BUZZER_ON();else BUZZER_OFF();
        if((elapsed/ALARM_LED_BLINK_MS)%2U==0) LED_R_ON();else LED_R_OFF();
    } else if(level==ALARM_LEVEL_NOTIFY) {
        uint32_t t=elapsed%NOTIFY_PERIOD_MS;
        uint32_t end=NOTIFY_BEEP_ON_MS*2U+NOTIFY_BEEP_OFF_MS;
        if(elapsed>=end) notify_latched=0;
        if(t<NOTIFY_BEEP_ON_MS || (t>=NOTIFY_BEEP_ON_MS+NOTIFY_BEEP_OFF_MS && t<end)) BUZZER_ON();else BUZZER_OFF();
    }
}
