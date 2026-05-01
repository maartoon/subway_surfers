#include <stdio.h>
#include "platform.h"
#include "lw_usb/GenericMacros.h"
#include "lw_usb/GenericTypeDefs.h"
#include "lw_usb/MAX3421E.h"
#include "lw_usb/USB.h"
#include "lw_usb/usb_ch9.h"
#include "lw_usb/transfer.h"
#include "lw_usb/HID.h"
#include "hdmi_text_controller.h"

#include "xparameters.h"
#include <xgpio.h>

extern HID_DEVICE hid_device;

static XGpio Gpio_hex;

static BYTE addr = 1; 				//hard-wired USB address
const char* const devclasses[] = { " Uninitialized", " HID Keyboard", " HID Mouse", " Mass storage" };

static int get_lane_x(int lane, int y_pos) {
	int row_depth = y_pos - HORIZON_Y;
	int road_half_width;
	int road_left;
	int lane_width;

	if (row_depth < 0) {
		row_depth = 0;
	}

	road_half_width = 48 + (row_depth >> 1);
	road_left = 320 - road_half_width;
	lane_width = (road_half_width * 2) / NUM_LANES;

	return road_left + lane * lane_width + (lane_width / 2) - (PLAYER_SPRITE_W / 2);
}

static int report_has_key(const BOOT_KBD_REPORT *report, BYTE keycode) {
	for (int i = 0; i < 6; i++) {
		if (report->keycode[i] == keycode) {
			return 1;
		}
	}
	return 0;
}

static void initialize_game_registers(void) {
	hdmi_ctrl->GAME_CTRL = GAME_STATE_MENU;
	hdmi_ctrl->PLAYER_X = get_lane_x(1, PLAYER_BASE_Y);
	hdmi_ctrl->PLAYER_Y = PLAYER_BASE_Y;
	hdmi_ctrl->PLAYER_STATE = PLAYER_RUN;
	hdmi_ctrl->FENCE_X = 0;
	hdmi_ctrl->FENCE_Y = 0;
	hdmi_ctrl->FENCE_VIS = 0;
	hdmi_ctrl->CLOVER_X = 0;
	hdmi_ctrl->CLOVER_Y = 0;
	hdmi_ctrl->CLOVER_VIS = 0;
	hdmi_ctrl->SCORE = 0;
}

BYTE GetDriverandReport() {
	BYTE i;
	BYTE rcode;
	BYTE device = 0xFF;
	BYTE tmpbyte;

	DEV_RECORD* tpl_ptr;
	xil_printf("Reached USB_STATE_RUNNING (0x40)\n");
	for (i = 1; i < USB_NUMDEVICES; i++) {
		tpl_ptr = GetDevtable(i);
		if (tpl_ptr->epinfo != NULL) {
			xil_printf("Device: %d", i);
			xil_printf("%s \n", devclasses[tpl_ptr->devclass]);
			device = tpl_ptr->devclass;
		}
	}
	//Query rate and protocol
	rcode = XferGetIdle(addr, 0, hid_device.interface, 0, &tmpbyte);
	if (rcode) {   //error handling
		xil_printf("GetIdle Error. Error code: ");
		xil_printf("%x \n", rcode);
	} else {
		xil_printf("Update rate: ");
		xil_printf("%x \n", tmpbyte);
	}
	xil_printf("Protocol: ");
	rcode = XferGetProto(addr, 0, hid_device.interface, &tmpbyte);
	if (rcode) {   //error handling
		xil_printf("GetProto Error. Error code ");
		xil_printf("%x \n", rcode);
	} else {
		xil_printf("%d \n", tmpbyte);
	}
	return device;
}

void printHex (u32 data, unsigned channel)
{
	XGpio_DiscreteWrite (&Gpio_hex, channel, data);
}

int main() {
    init_platform();
    XGpio_Initialize(&Gpio_hex, XPAR_GPIO_USB_KEYCODE_DEVICE_ID);
   	XGpio_SetDataDirection(&Gpio_hex, 1, 0x00000000); //configure hex display GPIO
   	XGpio_SetDataDirection(&Gpio_hex, 2, 0x00000000); //configure hex display GPIO


   	BYTE rcode;
	BOOT_MOUSE_REPORT buf;		//USB mouse report
	BOOT_KBD_REPORT kbdbuf;
	BOOT_KBD_REPORT prev_kbdbuf = {0};

	BYTE runningdebugflag = 0;//flag to dump out a bunch of information when we first get to USB_STATE_RUNNING
	BYTE errorflag = 0; //flag once we get an error device so we don't keep dumping out state info
	BYTE device = 0xFF;

	int game_state = GAME_STATE_MENU;
	int player_lane = 1;
	int player_state = PLAYER_RUN;
	int jump_timer = 0;
	int score = 0;

	initialize_game_registers();
	textHDMIColorClr();
	for (int i = 0; i < 16; i++) {
		setColorPalette(i, colors[i].red, colors[i].green, colors[i].blue);
	}
	textHDMIDrawColorText("SUBWAY SURFERS", 33, 12, 0, 15);
	textHDMIDrawColorText("Press ENTER to start", 30, 16, 0, 10);

	xil_printf("initializing MAX3421E...\n");
	MAX3421E_init();
	xil_printf("initializing USB...\n");
	USB_init();
	while (1) {
		MAX3421E_Task();
		USB_Task();
		if (GetUsbTaskState() == USB_STATE_RUNNING) {
			if (!runningdebugflag) {
				runningdebugflag = 1;
				device = GetDriverandReport();
				for (int i = 0; i < 6; i++) {
					prev_kbdbuf.keycode[i] = 0;
				}
			} else if (device == HID_K) {
				int left_now;
				int right_now;
				int jump_now;
				int duck_now;
				int enter_now;
				int left_prev;
				int right_prev;
				int jump_prev;
				int enter_prev;
				int left_edge;
				int right_edge;
				int jump_edge;
				int enter_edge;
				int player_y;

				//run keyboard debug polling
				rcode = kbdPoll(&kbdbuf);
				if (rcode == hrNAK) {
					for (int i = 0; i < 6; i++) {
						kbdbuf.keycode[i] = prev_kbdbuf.keycode[i];
					}
				} else if (rcode) {
					xil_printf("Rcode: ");
					xil_printf("%x \n", rcode);
					continue;
				}

				//Outputs the first 4 keycodes using the USB GPIO channel 1
				printHex(kbdbuf.keycode[0] + (kbdbuf.keycode[1] << 8) + (kbdbuf.keycode[2] << 16) + (kbdbuf.keycode[3] << 24), 1);
				printHex(kbdbuf.keycode[4] + (kbdbuf.keycode[5] << 8), 2);

				left_now = report_has_key(&kbdbuf, 0x04) || report_has_key(&kbdbuf, 0x50);
				right_now = report_has_key(&kbdbuf, 0x07) || report_has_key(&kbdbuf, 0x4F);
				jump_now = report_has_key(&kbdbuf, 0x1A) || report_has_key(&kbdbuf, 0x52);
				duck_now = report_has_key(&kbdbuf, 0x16) || report_has_key(&kbdbuf, 0x51);
				enter_now = report_has_key(&kbdbuf, 0x28);

				left_prev = report_has_key(&prev_kbdbuf, 0x04) || report_has_key(&prev_kbdbuf, 0x50);
				right_prev = report_has_key(&prev_kbdbuf, 0x07) || report_has_key(&prev_kbdbuf, 0x4F);
				jump_prev = report_has_key(&prev_kbdbuf, 0x1A) || report_has_key(&prev_kbdbuf, 0x52);
				enter_prev = report_has_key(&prev_kbdbuf, 0x28);

				left_edge = left_now && !left_prev;
				right_edge = right_now && !right_prev;
				jump_edge = jump_now && !jump_prev;
				enter_edge = enter_now && !enter_prev;

				if (game_state == GAME_STATE_MENU) {
					if (enter_edge) {
						game_state = GAME_STATE_PLAYING;
						player_lane = 1;
						player_state = PLAYER_RUN;
						jump_timer = 0;
						score = 0;
						textHDMIColorClr();
					}
				} else if (game_state == GAME_STATE_PLAYING) {
					if (left_edge && player_lane > 0) {
						player_lane--;
					}
					if (right_edge && player_lane < (NUM_LANES - 1)) {
						player_lane++;
					}

					if (jump_edge && player_state == PLAYER_RUN) {
						player_state = PLAYER_JUMP;
						jump_timer = 30;
					}

					if (player_state == PLAYER_JUMP) {
						if (jump_timer > 0) {
							jump_timer--;
						} else {
							player_state = PLAYER_RUN;
						}
					} else if (duck_now) {
						player_state = PLAYER_DUCK;
					} else if (player_state == PLAYER_DUCK) {
						player_state = PLAYER_RUN;
					}

					player_y = PLAYER_BASE_Y;
					if (player_state == PLAYER_JUMP) {
						player_y = PLAYER_BASE_Y - PLAYER_JUMP_HEIGHT;
					}

					hdmi_ctrl->GAME_CTRL = GAME_STATE_PLAYING;
					hdmi_ctrl->PLAYER_X = get_lane_x(player_lane, PLAYER_BASE_Y);
					hdmi_ctrl->PLAYER_Y = player_y;
					hdmi_ctrl->PLAYER_STATE = player_state;
					hdmi_ctrl->FENCE_VIS = 0;
					hdmi_ctrl->CLOVER_VIS = 0;
					hdmi_ctrl->SCORE = score;
				}

				for (int i = 0; i < 6; i++) {
					prev_kbdbuf.keycode[i] = kbdbuf.keycode[i];
				}

				sleepframe(1);
			}

			else if (device == HID_M) {
				rcode = mousePoll(&buf);
				if (rcode == hrNAK) {
					//NAK means no new data
					continue;
				} else if (rcode) {
					xil_printf("Rcode: ");
					xil_printf("%x \n", rcode);
					continue;
				}
				xil_printf("X displacement: ");
				xil_printf("%d ", (signed char) buf.Xdispl);
				xil_printf("Y displacement: ");
				xil_printf("%d ", (signed char) buf.Ydispl);
				xil_printf("Buttons: ");
				xil_printf("%x\n", buf.button);
			}
		} else if (GetUsbTaskState() == USB_STATE_ERROR) {
			if (!errorflag) {
				errorflag = 1;
				xil_printf("USB Error State\n");
				//print out string descriptor here
			}
		} else //not in USB running state
		{

			xil_printf("USB task state: ");
			xil_printf("%x\n", GetUsbTaskState());
			if (runningdebugflag) {	//previously running, reset USB hardware just to clear out any funky state, HS/FS etc
				runningdebugflag = 0;
				device = 0xFF;
				MAX3421E_init();
				USB_init();
			}
			errorflag = 0;
		}

	}
    cleanup_platform();
	return 0;
}
