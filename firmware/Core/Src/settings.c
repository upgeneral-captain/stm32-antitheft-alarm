/* Two-page append journal. Commit word last; erasing the other page preserves
 * the last committed record through a power interruption. Last 2KB reserved. */
#include "main.h"
#include "settings.h"
#define PAGE0 0x0800F800UL
#define PAGE1 0x0800FC00UL
#define MAGIC 0xA17E5AFEUL
typedef struct {uint32_t seq,armed,check,commit;} Record;
static uint32_t sequence, last_address;
static uint8_t saved, healthy=1;
static uint8_t append(uint8_t armed) {
    uint32_t addr=last_address?last_address+sizeof(Record):PAGE0;
    uint32_t page=last_address?(last_address&~1023UL):PAGE0;
    /* Never rewrite a partially programmed entry after interrupted commit. */
    while(addr<page+1024U && (*(volatile uint32_t *)(uintptr_t)addr!=0xffffffffUL ||
          *(volatile uint32_t *)(uintptr_t)(addr+4)!=0xffffffffUL ||
          *(volatile uint32_t *)(uintptr_t)(addr+8)!=0xffffffffUL ||
          *(volatile uint32_t *)(uintptr_t)(addr+12)!=0xffffffffUL)) addr+=sizeof(Record);
    HAL_FLASH_Unlock();
    if(addr>=page+1024U) {
        page=page==PAGE0?PAGE1:PAGE0;addr=page;
        FLASH_EraseInitTypeDef e={0};uint32_t error;
        e.TypeErase=FLASH_TYPEERASE_PAGES;e.PageAddress=page;e.NbPages=1;
        if(HAL_FLASHEx_Erase(&e,&error)!=HAL_OK) {HAL_FLASH_Lock();healthy=0;return 0;}
    }
    Record r={sequence+1U,armed,0,MAGIC};r.check=r.seq^r.armed^MAGIC;
    const uint32_t words[]={r.seq,r.armed,r.check,r.commit};
    for(uint32_t i=0;i<4;i++) if(HAL_FLASH_Program(FLASH_TYPEPROGRAM_WORD,addr+4U*i,words[i])!=HAL_OK) {
        HAL_FLASH_Lock();healthy=0;return 0;
    }
    HAL_FLASH_Lock();last_address=addr;sequence=r.seq;saved=armed;return 1;
}
uint8_t Settings_Load(void) {
    sequence=last_address=0;saved=0;healthy=1;
    for(uint32_t addr=PAGE0;addr<PAGE1+1024U;addr+=sizeof(Record)) {
        const Record *r=(const Record *)(uintptr_t)addr;
        if(r->commit==MAGIC && r->armed<=1 && r->check==(r->seq^r->armed^MAGIC) &&
           (!last_address || (int32_t)(r->seq-sequence)>0)) {
            sequence=r->seq;saved=(uint8_t)r->armed;last_address=addr;
        }
    }
    append(saved);return saved;
}
uint8_t Settings_Save(uint8_t armed) {return healthy && (saved==armed || append(armed));}
uint32_t Settings_BootId(void) {return sequence;}
