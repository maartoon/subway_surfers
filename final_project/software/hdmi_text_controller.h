#ifndef HDMI_TEXT_CONTROLLER_H
#define HDMI_TEXT_CONTROLLER_H


/****************** Include Files ********************/
#include "xil_types.h"
#include "xstatus.h"
#include "xparameters.h"

#define COLUMNS 80
#define ROWS 30
#define PALETTE_START 0x2000
#define GAME_REG_START 0x2030

#define GAME_STATE_MENU 0
#define GAME_STATE_PLAYING 1
#define GAME_STATE_GAMEOVER 2

#define PLAYER_RUN 0
#define PLAYER_JUMP 1
#define PLAYER_DUCK 2

#define HORIZON_Y 160
#define PLAYER_BASE_Y 380
#define PLAYER_JUMP_HEIGHT 60
#define PLAYER_SPRITE_W 40
#define PLAYER_SPRITE_H 50
#define FENCE_W 50
#define FENCE_H 50
#define CLOVER_W 40
#define CLOVER_H 50

#define NUM_LANES 3

#define STUDENT1NETID "martinx3"
#define STUDENT2NETID "miafang2"

struct TEXT_HDMI_STRUCT {
	uint8_t             VRAM [ROWS*COLUMNS*2]; //80 * 30 * 2 = 4800 bytes (0x0000 to 0x12BF) //Week 2 - extended VRAM
	//declare palette registers here, make sure you properly pad in order to correctly account for
	//gap in address map between VRAM and start of palette and control registers
	uint8_t 			PAD[0x2000 - ROWS*COLUMNS*2]; // 0x2000 - 4800
	uint32_t 			PALETTE[8];// 0x800 to 0x807
	uint32_t            FRAME_COUNT; //control registers should appear immediately after palette
	uint32_t            DRAWX;
	uint32_t            DRAWY;
	uint32_t            RESERVED_80B;
	uint32_t            GAME_CTRL;     // 0x80C
	uint32_t            PLAYER_X;      // 0x80D
	uint32_t            PLAYER_Y;      // 0x80E
	uint32_t            PLAYER_STATE;  // 0x80F
	uint32_t            FENCE_X;       // 0x810
	uint32_t            FENCE_Y;       // 0x811
	uint32_t            FENCE_VIS;     // 0x812
	uint32_t            CLOVER_X;      // 0x813
	uint32_t            CLOVER_Y;      // 0x814
	uint32_t            CLOVER_VIS;    // 0x815
	uint32_t            SCORE;         // 0x816
	uint32_t            FENCE_W_S;     // 0x817
	uint32_t            FENCE_H_S;     // 0x818
	uint32_t            FENCE_SCALE_INV; // 0x819
	uint32_t            CLOVER_W_S;    // 0x81A
	uint32_t            CLOVER_H_S;    // 0x81B
	uint32_t            CLOVER_SCALE_INV; // 0x81C
};

struct COLOR{
	char name [20];
	uint8_t red;
	uint8_t green;
	uint8_t blue;
};


//you may have to change this line depending on your platform designer
static volatile struct TEXT_HDMI_STRUCT* hdmi_ctrl = (volatile struct TEXT_HDMI_STRUCT*)XPAR_HDMI_GRAPHICS_CONTROLLER_0_AXI_BASEADDR;

//CGA colors with names
static struct COLOR colors[]={
    {"black",          0x0, 0x0, 0x0},
	{"blue",           0x0, 0x0, 0xa},
    {"green",          0x0, 0xa, 0x0},
	{"cyan",           0x0, 0xa, 0xa},
    {"red",            0xa, 0x0, 0x0},
	{"magenta",        0xa, 0x0, 0xa},
    {"brown",          0xa, 0x5, 0x0},
	{"light gray",     0xa, 0xa, 0xa},
    {"dark gray",      0x5, 0x5, 0x5},
	{"light blue",     0x5, 0x5, 0xf},
    {"light green",    0x5, 0xf, 0x5},
	{"light cyan",     0x5, 0xf, 0xf},
    {"light red",      0xf, 0x5, 0x5},
	{"light magenta",  0xf, 0x5, 0xf},
    {"yellow",         0xf, 0xf, 0x5},
	{"white",          0xf, 0xf, 0xf}
};

/**************************** Type Definitions *****************************/
/**
 *
 * Write a value to a HDMI_TEXT_CONTROLLER register. A 32 bit write is performed.
 * If the component is implemented in a smaller width, only the least
 * significant data is written.
 *
 * @param   BaseAddress is the base address of the HDMI_TEXT_CONTROLLERdevice.
 * @param   RegOffset is the register offset from the base to write to.
 * @param   Data is the data written to the register.
 *
 * @return  None.
 *
 * @note
 * C-style signature:
 * 	void HDMI_TEXT_CONTROLLER_mWriteReg(u32 BaseAddress, unsigned RegOffset, u32 Data)
 *
 */
#define HDMI_TEXT_CONTROLLER_mWriteReg(BaseAddress, RegOffset, Data) \
  	Xil_Out32((BaseAddress) + (RegOffset), (u32)(Data))

/**
 *
 * Read a value from a HDMI_TEXT_CONTROLLER register. A 32 bit read is performed.
 * If the component is implemented in a smaller width, only the least
 * significant data is read from the register. The most significant data
 * will be read as 0.
 *
 * @param   BaseAddress is the base address of the HDMI_TEXT_CONTROLLER device.
 * @param   RegOffset is the register offset from the base to write to.
 *
 * @return  Data is the data from the register.
 *
 * @note
 * C-style signature:
 * 	u32 HDMI_TEXT_CONTROLLER_mReadReg(u32 BaseAddress, unsigned RegOffset)
 *
 */
#define HDMI_TEXT_CONTROLLER_mReadReg(BaseAddress, RegOffset) \
    Xil_In32((BaseAddress) + (RegOffset))

/************************** Function Prototypes ****************************/
/**
 *
 * Run a self-test on the driver/device. Note this may be a destructive test if
 * resets of the device are performed.
 *
 * If the hardware system is not built correctly, this function may never
 * return to the caller.
 *
 * @param   baseaddr_p is the base address of the HDMI_TEXT_CONTROLLER instance to be worked on.
 *
 * @return
 *
 *    - XST_SUCCESS   if all self-test code passed
 *    - XST_FAILURE   if any self-test code failed
 *
 * @note    Caching must be turned off for this function to work.
 * @note    Self test may fail if data memory and device are not on the same bus.
 *
 */
 

void textHDMIColorClr();
void textHDMIDrawColorText(char* str, int x, int y, uint8_t background, uint8_t foreground);
void setColorPalette (uint8_t color, uint8_t red, uint8_t green, uint8_t blue); //Fill in this code
void sleepframe(uint32_t frames);
void paletteTest();
void textHDMIColorScreenSaver();
void hdmiTestWeek2(); //call this for your Week 2 demo

#endif // HDMI_TEXT_CONTROLLER_H
