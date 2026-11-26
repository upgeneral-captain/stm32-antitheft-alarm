/**
  ******************************************************************************
  * @file    oled.c
  * @brief   SSD1306 OLED 128x64 I2C 驱动（页寻址 + 整行刷新）
  *
  * 显存布局：oled_buf[8][128]
  *   oled_buf[page][x] 的 bit0~bit7 对应 y = page*8 + 0 ... page*8 + 7
  *
  * 刷新策略：每一行写之前先清空该行显存，再把字模画进去，最后只刷这一页。
  *   -> 不会有残影，且一次 I2C 只传 128 字节，刷新快。
  ******************************************************************************
  */

#include "oled.h"
#include <string.h>

/* ========================== 模块内部变量 ========================== */
static I2C_HandleTypeDef *oled_i2c = NULL;
static uint8_t  oled_ok = 0;             /* I2C 通信正常标志 */

/* 显存：8 页 × 128 列 = 1024 字节 */
static uint8_t  oled_buf[8][OLED_WIDTH];
static uint8_t sent[8][OLED_WIDTH], dirty[8], scan_page, scan_col;
static uint32_t retry_at;

/* ========================== 5x7 字库 ==========================
 * 每字符 5 列，每列 1 字节（低 7 位有效，bit0 在最上面）
 * 添加新字符：按 {'A', {0x7E,0x11,0x11,0x11,0x7E}} 格式插入即可
 */
typedef struct {
    char    ch;
    uint8_t col[5];
} OLED_Font;

static const OLED_Font font5x7[] = {
    {' ', {0x00,0x00,0x00,0x00,0x00}},
    {'.', {0x00,0x60,0x60,0x00,0x00}},
    {',', {0x00,0x40,0x60,0x20,0x00}},
    {':', {0x00,0x36,0x36,0x00,0x00}},
    {'-', {0x08,0x08,0x08,0x08,0x08}},
    {'_', {0x40,0x40,0x40,0x40,0x40}},
    {'/', {0x20,0x10,0x08,0x04,0x02}},
    {'>', {0x41,0x22,0x14,0x08,0x00}},
    {'<', {0x08,0x14,0x22,0x41,0x00}},
    {'!', {0x00,0x00,0x5F,0x00,0x00}},
    {'%', {0x62,0x64,0x08,0x13,0x23}},
    {'0', {0x3E,0x51,0x49,0x45,0x3E}},
    {'1', {0x00,0x42,0x7F,0x40,0x00}},
    {'2', {0x42,0x61,0x51,0x49,0x46}},
    {'3', {0x21,0x41,0x45,0x4B,0x31}},
    {'4', {0x18,0x14,0x12,0x7F,0x10}},
    {'5', {0x27,0x45,0x45,0x45,0x39}},
    {'6', {0x3C,0x4A,0x49,0x49,0x30}},
    {'7', {0x01,0x71,0x09,0x05,0x03}},
    {'8', {0x36,0x49,0x49,0x49,0x36}},
    {'9', {0x06,0x49,0x49,0x29,0x1E}},
    {'A', {0x7E,0x11,0x11,0x11,0x7E}},
    {'B', {0x7F,0x49,0x49,0x49,0x36}},
    {'C', {0x3E,0x41,0x41,0x41,0x22}},
    {'D', {0x7F,0x41,0x41,0x22,0x1C}},
    {'E', {0x7F,0x49,0x49,0x49,0x41}},
    {'F', {0x7F,0x09,0x09,0x09,0x01}},
    {'G', {0x3E,0x41,0x49,0x49,0x7A}},
    {'H', {0x7F,0x08,0x08,0x08,0x7F}},
    {'I', {0x00,0x41,0x7F,0x41,0x00}},
    {'J', {0x20,0x40,0x41,0x3F,0x01}},
    {'K', {0x7F,0x08,0x14,0x22,0x41}},
    {'L', {0x7F,0x40,0x40,0x40,0x40}},
    {'M', {0x7F,0x02,0x04,0x02,0x7F}},
    {'N', {0x7F,0x04,0x08,0x10,0x7F}},
    {'O', {0x3E,0x41,0x41,0x41,0x3E}},
    {'P', {0x7F,0x09,0x09,0x09,0x06}},
    {'Q', {0x3E,0x41,0x51,0x21,0x5E}},
    {'R', {0x7F,0x09,0x19,0x29,0x46}},
    {'S', {0x46,0x49,0x49,0x49,0x31}},
    {'T', {0x01,0x01,0x7F,0x01,0x01}},
    {'U', {0x3F,0x40,0x40,0x40,0x3F}},
    {'V', {0x1F,0x20,0x40,0x20,0x1F}},
    {'W', {0x3F,0x40,0x38,0x40,0x3F}},
    {'X', {0x63,0x14,0x08,0x14,0x63}},
    {'Y', {0x07,0x08,0x70,0x08,0x07}},
    {'Z', {0x61,0x51,0x49,0x45,0x43}},
    {'g', {0x38,0x54,0x54,0x54,0x7C}},     /* 单位 g（小写） */
    {0,   {0,0,0,0,0}}                      /* 结束标志 */
};

/* ========================== 底层 I2C ========================== */

/* 写命令（0x00 控制字节 + 命令），一次最多 15 个 */
static uint8_t OLED_CmdN(const uint8_t *cmd, uint16_t len)
{
    uint8_t pkt[16];

    if (len > 15) len = 15;
    pkt[0] = 0x00;                        /* Co=0 D/C#=0 -> 命令 */
    memcpy(&pkt[1], cmd, len);

    if (HAL_I2C_Master_Transmit(oled_i2c, OLED_I2C_ADDR, pkt, (uint16_t)(len + 1), 3) != HAL_OK) {
        oled_ok = 0;
        return 0;
    }
    oled_ok = 1;
    return 1;
}

static uint8_t OLED_Cmd(uint8_t cmd)
{
    return OLED_CmdN(&cmd, 1);
}

/* 写数据（0x40 控制字节 + 数据），16 字节一包 */
static uint8_t OLED_Data(const uint8_t *data, uint16_t len)
{
    uint8_t  pkt[17];
    uint16_t i, n;

    pkt[0] = 0x40;                        /* Co=0 D/C#=1 -> 数据 */
    for (i = 0; i < len; i += 16) {
        n = (uint16_t)((len - i > 16) ? 16 : (len - i));
        memcpy(&pkt[1], &data[i], n);
        if (HAL_I2C_Master_Transmit(oled_i2c, OLED_I2C_ADDR, pkt, (uint16_t)(n + 1), 3) != HAL_OK) {
            oled_ok = 0;
            return 0;
        }
    }
    oled_ok = 1;
    return 1;
}

/* 把某一页（128 字节）刷到屏幕 */
static void OLED_FlushPage(uint8_t page) { if(page<8) dirty[page]=1; }
/* One 16-byte chunk (~2ms at 100kHz) per idle slot. Never flush full screens. */
void OLED_Task(void) {
    if(HAL_GetTick()-retry_at<100U) return;
    uint8_t attempts=0;
    while(!dirty[scan_page] && attempts++<8) scan_page=(scan_page+1U)%8U;
    if(!dirty[scan_page]) return;
    uint8_t cmds[3]={(uint8_t)(0xB0U|scan_page),(uint8_t)(scan_col&15U),(uint8_t)(0x10U|(scan_col>>4))};
    if(memcmp(sent[scan_page]+scan_col,oled_buf[scan_page]+scan_col,16)!=0) {
        if(!OLED_CmdN(cmds,3) || !OLED_Data(oled_buf[scan_page]+scan_col,16)) {retry_at=HAL_GetTick();return;}
        memcpy(sent[scan_page]+scan_col,oled_buf[scan_page]+scan_col,16);
    }
    scan_col+=16;
    if(scan_col>=128) {scan_col=0;dirty[scan_page]=0;scan_page=(scan_page+1U)%8U;}
}

/* ========================== 初始化 ========================== */

/**
 * @brief SSD1306 初始化（页寻址，兼容 0.96" 128x64 I2C 模块）
 */
void OLED_Init(I2C_HandleTypeDef *hi2c)
{
    static const uint8_t init_cmds[] = {
        0xAE,           /* 关显示 */
        0xD5, 0x80,     /* 时钟分频 */
        0xA8, 0x3F,     /* 多路复用 1/64 */
        0xD3, 0x00,     /* 显示偏移 0 */
        0x40,           /* 起始行 0 */
        0x8D, 0x14,     /* 开内部电荷泵（模块必备，否则不亮） */
        0x20, 0x02,     /* 页寻址模式 */
        0xA1,           /* 段重映射（左右方向） */
        0xC8,           /* COM 扫描方向（上下方向） */
        0xDA, 0x12,     /* COM 引脚配置 */
        0x81, 0xCF,     /* 对比度 */
        0xD9, 0xF1,     /* 预充电 */
        0xDB, 0x40,     /* VCOMH */
        0xA4,           /* 显示跟随显存 */
        0xA6,           /* 正常显示（非反色） */
        0xAF            /* 开显示 */
    };
    uint16_t i;

    oled_i2c = hi2c;
    memset(sent,0xff,sizeof(sent));
    oled_ok  = 0;

    /* 先探测地址；不成功也继续跑，方便区分“接线问题”和“初始化问题” */
    if (HAL_I2C_IsDeviceReady(hi2c, OLED_I2C_ADDR, 3, 100) == HAL_OK) {
        oled_ok = 1;
    }

    for (i = 0; i < sizeof(init_cmds); i++) {
        OLED_Cmd(init_cmds[i]);
    }
    OLED_Clear();
}

void OLED_Clear(void)
{
    uint8_t p;

    memset(oled_buf, 0x00, sizeof(oled_buf));
    for (p = 0; p < 8; p++) {
        OLED_FlushPage(p);
    }
}

uint8_t OLED_IsOK(void)
{
    return oled_ok;
}

/* ========================== 字符串 ========================== */

/* 查字模：找不到就用空格 */
static const uint8_t *OLED_Glyph(char c)
{
    const OLED_Font *p;

    for (p = font5x7; p->ch != 0; p++) {
        if (p->ch == c) return p->col;
    }
    return font5x7[0].col;
}

/**
 * @brief 在指定位置写一行字符串（先清空该行，再画字，然后刷该页）
 * @param x    起始列（像素，建议 0 / 6 的倍数）
 * @param line 行号 0~7
 */
void OLED_PrintLine(uint8_t x, uint8_t line, const char *str)
{
    const uint8_t *g;
    uint8_t col;
    uint8_t i;

    if (line > 7 || x >= OLED_WIDTH) return;

    /* 1) 清空整行，避免上一次的长字符串残留 */
    memset(oled_buf[line], 0x00, OLED_WIDTH);

    /* 2) 画字：每字符 6 像素宽（5 列字形 + 1 列空白） */
    col = x;
    while (*str && col < (OLED_WIDTH - 6)) {
        g = OLED_Glyph(*str);
        for (i = 0; i < 5; i++) {
            oled_buf[line][col + i] = g[i];
        }
        col = (uint8_t)(col + 6);
        str++;
    }

    /* 3) 刷新这一页 */
    OLED_FlushPage(line);
}

/* 把 float 格式化成字符串（不用 printf，省 Flash） */
static void FormatFloat(char *buf, float val, uint8_t intDigits, uint8_t fracDigits)
{
    uint32_t scale = 1;
    uint32_t ip, fp;
    uint8_t  n = 0;
    uint8_t  i;
    char     tmp[8];
    uint8_t  t = 0;

    if (val < 0.0f) {
        buf[n++] = '-';
        val = -val;
    }

    for (i = 0; i < fracDigits; i++) scale *= 10;

    ip = (uint32_t)val;
    fp = (uint32_t)((val - (float)ip) * (float)scale + 0.5f);
    if (fp >= scale && scale > 1) { ip += 1; fp -= scale; }

    /* 整数部分（至少 intDigits 位） */
    do {
        tmp[t++] = (char)('0' + (ip % 10));
        ip /= 10;
    } while (ip > 0 && t < sizeof(tmp) - 1);

    while (t < intDigits) tmp[t++] = '0';

    while (t > 0) {
        buf[n++] = tmp[--t];
    }

    /* 小数部分 */
    if (fracDigits > 0) {
        buf[n++] = '.';
        scale /= 10;
        while (scale > 0 && n < 14) {
            buf[n++] = (char)('0' + ((fp / scale) % 10));
            scale /= 10;
        }
    }
    buf[n] = '\0';
}

void OLED_PrintLineFloat(uint8_t x, uint8_t line, const char *head,
                         float val, uint8_t intDigits, uint8_t fracDigits,
                         const char *tail)
{
    char    s[32];
    char    num[16];
    uint8_t pos = 0;
    uint8_t i;

    if (head == NULL) head = "";
    if (tail == NULL) tail = "";

    FormatFloat(num, val, intDigits, fracDigits);

    /* 手写拼接（strcat 系列在这里会触发 -Wstringop-overflow 误报） */
    for (i = 0; head[i] != '\0' && pos < sizeof(s) - 1; i++) s[pos++] = head[i];
    for (i = 0; num[i]  != '\0' && pos < sizeof(s) - 1; i++) s[pos++] = num[i];
    for (i = 0; tail[i] != '\0' && pos < sizeof(s) - 1; i++) s[pos++] = tail[i];
    s[pos] = '\0';

    OLED_PrintLine(x, line, s);
}

void OLED_PrintLineNum(uint8_t x, uint8_t line, const char *head,
                       uint16_t num, uint8_t width, const char *tail)
{
    char    s[32];
    char    digits[8];
    uint8_t n = 0;
    uint8_t i;
    uint8_t pos = 0;

    if (head == NULL) head = "";
    if (tail == NULL) tail = "";

    if (num == 0) {
        digits[n++] = '0';
    } else {
        while (num > 0 && n < 5) {
            digits[n++] = (char)('0' + (num % 10));
            num /= 10;
        }
    }

    /* head */
    for (i = 0; head[i] != '\0' && pos < sizeof(s) - 1; i++) {
        s[pos++] = head[i];
    }
    /* 补足宽度（前导空格） */
    for (i = n; i < width && pos < sizeof(s) - 1; i++) {
        s[pos++] = ' ';
    }
    /* 数字：倒序输出 */
    for (i = n; i > 0 && pos < sizeof(s) - 1; i--) {
        s[pos++] = digits[i - 1];
    }
    /* tail */
    for (i = 0; tail[i] != '\0' && pos < sizeof(s) - 1; i++) {
        s[pos++] = tail[i];
    }
    s[pos] = '\0';

    OLED_PrintLine(x, line, s);
}

/* ========================== 进度条 ========================== */

/**
 * @brief 进度条：第 3 页区域（y = 24 ~ 31），120 像素宽，6 像素高
 * @param percent 0~100
 */
void OLED_DrawProgress(uint8_t percent)
{
    uint8_t x, y;
    uint8_t barPx;
    uint8_t bk[OLED_WIDTH];

    if (percent > 100) percent = 100;
    barPx = (uint8_t)((percent * 112U) / 100U);

    /* 先把第 3 页清空 */
    memset(oled_buf[1], 0x00, OLED_WIDTH);
    memcpy(bk, oled_buf[1], OLED_WIDTH);

    /* 外框：y=24（第3页 bit0）和 y=31（第3页 bit7） */
    for (x = 4; x < 124; x++) {
        oled_buf[1][x] |= 0x81;                 /* bit0 + bit7 */
    }
    /* 左边框 + 右边框（整列） */
    oled_buf[1][4]  = 0xFF;
    oled_buf[1][123] = 0xFF;

    /* 填充：y=26~29 对应 bit2~bit5 -> 0x3C */
    for (x = 6; x < (uint8_t)(6 + barPx) && x < 122; x++) {
        oled_buf[1][x] |= 0x3C;
    }

    OLED_FlushPage(1);

    (void)y;
    (void)bk;
}
