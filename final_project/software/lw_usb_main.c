#include <stdio.h>
#include <stdlib.h>
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
static const BYTE KEY_ENTER = 0x28;
static const BYTE KEY_ENTER_KP = 0x58;

static int get_lane_x(int lane, int y_pos, int sprite_w) {
	int row_depth = y_pos - HORIZON_Y;
	int road_half_width;
	int road_left;
	int road_width;
	int lane_midpoint;

	if (row_depth < 0) {
		row_depth = 0;
	}

	road_half_width = 64 + (row_depth >> 1);
	road_left = 320 - road_half_width;
	road_width = road_half_width * 2;
	
	lane_midpoint = road_left + (road_width * (2 * lane + 1)) / (2 * NUM_LANES);
	return lane_midpoint - (sprite_w / 2);
}

static void calc_scale(int y_pos, int base_w, int base_h, int *w_s, int *h_s, int *scale_inv) {
    int row_depth = y_pos - HORIZON_Y;
    if (row_depth < 0) row_depth = 0;
    
    // Scale quadratically/linearly to simulate perspective: 15/256 at horizon, 615/256 at bottom
    int scale_256 = 15 + (600 * row_depth) / 320;
    if (scale_256 < 5) scale_256 = 5; 
    
    *w_s = (base_w * scale_256) >> 8;
    *h_s = (base_h * scale_256) >> 8;
    *scale_inv = (256 * 256) / scale_256; 
}

static int get_speed_fp(int y_pos) {
    int row_depth = y_pos - HORIZON_Y;
    if (row_depth < 0) row_depth = 0;
    // Quadratic perspective speed: speed = base + (row_depth^2) / factor
    int speed_fp = 160 + (row_depth * row_depth) / 25;
    return speed_fp;
}

static int check_collision(int p_lane, int p_state, int o_lane, int o_y, int o_w_s, int o_h_s, int o_active) {
    if (!o_active) return 0;
    
    int depth_diff = o_y - PLAYER_BASE_Y;
    if (depth_diff < 0) depth_diff = -depth_diff;
    
    // Y-coordinate represents Z-depth. Only collide if overlapping in depth space!
    if (p_lane == o_lane && depth_diff < 25) {
        if (p_state == PLAYER_JUMP) return 0; // jump clears ground obstacle
        return 1;
    }
    return 0;
}

static int check_powerup(int p_lane, int p_state, int o_lane, int o_y, int o_w_s, int o_h_s, int o_active, int airborne) {
    if (!o_active) return 0;
    if (airborne && p_state != PLAYER_JUMP) return 0;
    
    int depth_diff = o_y - PLAYER_BASE_Y;
    if (depth_diff < 0) depth_diff = -depth_diff;
    
    if (p_lane == o_lane && depth_diff < 30) {
        return 1;
    }
    return 0;
}

static int get_airborne_y(int depth_y, int h_s) {
	int y = depth_y - PLAYER_JUMP_HEIGHT - (h_s / 2);
	if (y < HORIZON_Y) {
		y = HORIZON_Y;
	}
	return y;
}

static void write_fence_slot(int slot, int x, int y, int w_s, int h_s, int scale_inv, int active) {
	if (slot == 0) {
		hdmi_ctrl->FENCE_X = x;
		hdmi_ctrl->FENCE_Y = y;
		hdmi_ctrl->FENCE_W_S = w_s;
		hdmi_ctrl->FENCE_H_S = h_s;
		hdmi_ctrl->FENCE_SCALE_INV = scale_inv;
		hdmi_ctrl->FENCE_VIS = active;
	} else if (slot == 1) {
		hdmi_ctrl->FENCE2_X = x;
		hdmi_ctrl->FENCE2_Y = y;
		hdmi_ctrl->FENCE2_W_S = w_s;
		hdmi_ctrl->FENCE2_H_S = h_s;
		hdmi_ctrl->FENCE2_SCALE_INV = scale_inv;
		hdmi_ctrl->FENCE2_VIS = active;
	} else if (slot == 2) {
		hdmi_ctrl->FENCE3_X = x;
		hdmi_ctrl->FENCE3_Y = y;
		hdmi_ctrl->FENCE3_W_S = w_s;
		hdmi_ctrl->FENCE3_H_S = h_s;
		hdmi_ctrl->FENCE3_SCALE_INV = scale_inv;
		hdmi_ctrl->FENCE3_VIS = active;
	} else {
		hdmi_ctrl->FENCE4_X = x;
		hdmi_ctrl->FENCE4_Y = y;
		hdmi_ctrl->FENCE4_W_S = w_s;
		hdmi_ctrl->FENCE4_H_S = h_s;
		hdmi_ctrl->FENCE4_SCALE_INV = scale_inv;
		hdmi_ctrl->FENCE4_VIS = active;
	}
}

static void write_clover_slot(int slot, int x, int y, int w_s, int h_s, int scale_inv, int active) {
	if (slot == 0) {
		hdmi_ctrl->CLOVER_X = x;
		hdmi_ctrl->CLOVER_Y = y;
		hdmi_ctrl->CLOVER_W_S = w_s;
		hdmi_ctrl->CLOVER_H_S = h_s;
		hdmi_ctrl->CLOVER_SCALE_INV = scale_inv;
		hdmi_ctrl->CLOVER_VIS = active;
	} else if (slot == 1) {
		hdmi_ctrl->CLOVER2_X = x;
		hdmi_ctrl->CLOVER2_Y = y;
		hdmi_ctrl->CLOVER2_W_S = w_s;
		hdmi_ctrl->CLOVER2_H_S = h_s;
		hdmi_ctrl->CLOVER2_SCALE_INV = scale_inv;
		hdmi_ctrl->CLOVER2_VIS = active;
	} else {
		hdmi_ctrl->CLOVER3_X = x;
		hdmi_ctrl->CLOVER3_Y = y;
		hdmi_ctrl->CLOVER3_W_S = w_s;
		hdmi_ctrl->CLOVER3_H_S = h_s;
		hdmi_ctrl->CLOVER3_SCALE_INV = scale_inv;
		hdmi_ctrl->CLOVER3_VIS = active;
	}
}

static int report_has_key(const BOOT_KBD_REPORT *report, BYTE keycode) {
	for (int i = 0; i < 6; i++) {
		if (report->keycode[i] == keycode) {
			return 1;
		}
	}
	return 0;
}

static int reports_equal(const BOOT_KBD_REPORT *a, const BOOT_KBD_REPORT *b) {
	if (a->mod != b->mod || a->reserved != b->reserved) {
		return 0;
	}
	for (int i = 0; i < 6; i++) {
		if (a->keycode[i] != b->keycode[i]) {
			return 0;
		}
	}
	return 1;
}

static void debug_print_kbd_report(const BOOT_KBD_REPORT *report) {
	xil_printf("kbd mod=%x keys=%x %x %x %x %x %x\n",
			report->mod,
			report->keycode[0], report->keycode[1], report->keycode[2],
			report->keycode[3], report->keycode[4], report->keycode[5]);
}

static void initialize_game_registers(void) {
	hdmi_ctrl->GAME_CTRL = GAME_STATE_MENU;
	hdmi_ctrl->PLAYER_X = get_lane_x(1, PLAYER_BASE_Y, PLAYER_SPRITE_W);
	hdmi_ctrl->PLAYER_Y = PLAYER_BASE_Y;
	hdmi_ctrl->PLAYER_STATE = PLAYER_RUN;
	hdmi_ctrl->FENCE_X = 0;
	hdmi_ctrl->FENCE_Y = 0;
	hdmi_ctrl->FENCE_VIS = 0;
	hdmi_ctrl->CLOVER_X = 0;
	hdmi_ctrl->CLOVER_Y = 0;
	hdmi_ctrl->CLOVER_VIS = 0;
	hdmi_ctrl->SCORE = 0;
	
	hdmi_ctrl->FENCE_W_S = FENCE_W;
	hdmi_ctrl->FENCE_H_S = FENCE_H;
	hdmi_ctrl->FENCE_SCALE_INV = 256;
	hdmi_ctrl->FENCE2_VIS = 0;
	hdmi_ctrl->FENCE3_VIS = 0;
	hdmi_ctrl->FENCE4_VIS = 0;
	
	hdmi_ctrl->CLOVER_W_S = CLOVER_W;
	hdmi_ctrl->CLOVER_H_S = CLOVER_H;
	hdmi_ctrl->CLOVER_SCALE_INV = 256;
	hdmi_ctrl->CLOVER2_VIS = 0;
	hdmi_ctrl->CLOVER2_W_S = CLOVER_W;
	hdmi_ctrl->CLOVER2_H_S = CLOVER_H;
	hdmi_ctrl->CLOVER2_SCALE_INV = 256;
	hdmi_ctrl->CLOVER3_VIS = 0;
	hdmi_ctrl->CLOVER3_W_S = CLOVER_W;
	hdmi_ctrl->CLOVER3_H_S = CLOVER_H;
	hdmi_ctrl->CLOVER3_SCALE_INV = 256;
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
	BYTE last_usb_state = 0xFF;

	int game_state = GAME_STATE_MENU;
	int player_lane = 1;
	int player_state = PLAYER_RUN;
	int jump_timer = 0;
	int jump_switches = 0;
	int lane_switch_cooldown = 0;
	int score = 0;
	
	int current_x = get_lane_x(1, PLAYER_BASE_Y, PLAYER_SPRITE_W);
	
	struct { int active; int lane; int y_fp; } fences[4] = {{0}};

	struct { int active; int lane; int y_fp; int airborne; } clovers[3] = {{0}};

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
		if (last_usb_state != GetUsbTaskState()) {
			last_usb_state = GetUsbTaskState();
			xil_printf("USB state -> %x\n", last_usb_state);
		}
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
					kbdbuf.mod = prev_kbdbuf.mod;
					kbdbuf.reserved = prev_kbdbuf.reserved;
				} else if (rcode) {
					xil_printf("Rcode: ");
					xil_printf("%x \n", rcode);
					continue;
				}

				if (!reports_equal(&kbdbuf, &prev_kbdbuf)) {
					debug_print_kbd_report(&kbdbuf);
				}

				//Outputs the first 4 keycodes using the USB GPIO channel 1
				printHex(kbdbuf.keycode[0] + (kbdbuf.keycode[1] << 8) + (kbdbuf.keycode[2] << 16) + (kbdbuf.keycode[3] << 24), 1);
				printHex(kbdbuf.keycode[4] + (kbdbuf.keycode[5] << 8), 2);

				left_now = report_has_key(&kbdbuf, 0x04) || report_has_key(&kbdbuf, 0x50);
				right_now = report_has_key(&kbdbuf, 0x07) || report_has_key(&kbdbuf, 0x4F);
				jump_now = report_has_key(&kbdbuf, 0x1A) || report_has_key(&kbdbuf, 0x52);
				duck_now = report_has_key(&kbdbuf, 0x16) || report_has_key(&kbdbuf, 0x51);
				enter_now = report_has_key(&kbdbuf, KEY_ENTER) || report_has_key(&kbdbuf, KEY_ENTER_KP);

				left_prev = report_has_key(&prev_kbdbuf, 0x04) || report_has_key(&prev_kbdbuf, 0x50);
				right_prev = report_has_key(&prev_kbdbuf, 0x07) || report_has_key(&prev_kbdbuf, 0x4F);
				jump_prev = report_has_key(&prev_kbdbuf, 0x1A) || report_has_key(&prev_kbdbuf, 0x52);
				enter_prev = report_has_key(&prev_kbdbuf, KEY_ENTER) || report_has_key(&prev_kbdbuf, KEY_ENTER_KP);

				left_edge = left_now && !left_prev;
				right_edge = right_now && !right_prev;
				jump_edge = jump_now && !jump_prev;
				enter_edge = enter_now && !enter_prev;

				if (game_state == GAME_STATE_MENU) {
					// Accept either edge or held Enter to avoid missing a transition due to timing.
					if (enter_edge || enter_now) {
						game_state = GAME_STATE_PLAYING;
						player_lane = 1;
						player_state = PLAYER_RUN;
						jump_timer = 0;
						jump_switches = 0;
						lane_switch_cooldown = 0;
						current_x = get_lane_x(1, PLAYER_BASE_Y, PLAYER_SPRITE_W);
						score = 0;
						for(int i=0; i<4; i++) fences[i].active = 0;
						for(int i=0; i<3; i++) clovers[i].active = 0;
						srand(hdmi_ctrl->FRAME_COUNT);
						xil_printf("MENU -> PLAYING\n");
						textHDMIColorClr();
					}
				} else if (game_state == GAME_STATE_PLAYING) {
				    if (lane_switch_cooldown > 0) lane_switch_cooldown--;
				    
					if (left_edge && player_lane > 0 && lane_switch_cooldown == 0) {
					    if (player_state != PLAYER_JUMP || jump_switches < 1) {
						    player_lane--;
						    lane_switch_cooldown = 15; // 15 frame cooldown
						    if (player_state == PLAYER_JUMP) jump_switches++;
						}
					}
					if (right_edge && player_lane < (NUM_LANES - 1) && lane_switch_cooldown == 0) {
					    if (player_state != PLAYER_JUMP || jump_switches < 1) {
						    player_lane++;
						    lane_switch_cooldown = 15; // 15 frame cooldown
						    if (player_state == PLAYER_JUMP) jump_switches++;
						}
					}

					if (jump_edge && player_state == PLAYER_RUN) {
						player_state = PLAYER_JUMP;
						jump_timer = 24; // 24 frames for asymmetric jump
						jump_switches = 0;
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

					if (player_state == PLAYER_JUMP) {
					    // Asymmetric jump: fast ascent (10 frames), softer descent (14 frames)
					    int h;
					    int t = 24 - jump_timer; // 0 to 24
					    if (t <= 10) {
					        int inv = 10 - t;
					        h = PLAYER_JUMP_HEIGHT - (PLAYER_JUMP_HEIGHT * inv * inv) / 100;
					    } else {
					        int dt = t - 10;
					        h = PLAYER_JUMP_HEIGHT - (PLAYER_JUMP_HEIGHT * dt * dt) / 196;
					    }
						player_y = PLAYER_BASE_Y - h;
					} else {
					    player_y = PLAYER_BASE_Y;
					}
					
					// Dash animation for lane switching ("whip" / ease-out effect)
					int target_x = get_lane_x(player_lane, PLAYER_BASE_Y, PLAYER_SPRITE_W);
					int dx = target_x - current_x;
					if (dx != 0) {
					    int step = dx / 4; // Snappy ease-out fraction
					    if (step == 0) step = (dx > 0) ? 4 : -4; // Minimum speed
					    
					    int abs_dx = (dx > 0) ? dx : -dx;
					    int abs_step = (step > 0) ? step : -step;
					    
					    if (abs_dx <= abs_step) current_x = target_x;
					    else current_x += step;
					}

					// Obstacle logic
					int free_count = 0;
					int spawn_mod = 34 - (score / 120);
					if (spawn_mod < 16) spawn_mod = 16;
					for (int i=0; i<4; i++) if (!fences[i].active) free_count++;

					if (free_count > 0 && (rand() % spawn_mod) == 0) {
					    int pattern = rand() % 12;
					    int spawn_y_fp = HORIZON_Y << 8;
					    if (pattern < 6 || free_count == 1) {
					        for (int i=0; i<4; i++) {
					            if (!fences[i].active) {
					                fences[i].lane = rand() % NUM_LANES;
					                fences[i].y_fp = spawn_y_fp;
					                fences[i].active = 1;
					                break;
					            }
					        }
					    } else if (pattern < 10 && free_count >= 2) {
					        int lane_a = rand() % NUM_LANES;
					        int lane_b = (lane_a + 1 + (rand() % 2)) % NUM_LANES;
					        int spawned = 0;
					        for (int i=0; i<4; i++) {
					            if (!fences[i].active && spawned < 2) {
					                fences[i].lane = (spawned == 0) ? lane_a : lane_b;
					                fences[i].y_fp = spawn_y_fp;
					                fences[i].active = 1;
					                spawned++;
					            }
					        }
					    } else if (free_count >= 3) {
					        int l = 0;
					        for (int i=0; i<4; i++) {
					            if (!fences[i].active && l < 3) {
					                fences[i].lane = l++;
					                fences[i].y_fp = spawn_y_fp;
					                fences[i].active = 1;
					            }
					        }
					    }
					}
					
					for (int i=0; i<4; i++) {
					    if (fences[i].active) {
						    fences[i].y_fp += get_speed_fp(fences[i].y_fp >> 8);
						    int obs_y = fences[i].y_fp >> 8;
						    if (obs_y > 480) {
							    fences[i].active = 0;
							    write_fence_slot(i, 0, 0, FENCE_W, FENCE_H, 256, 0);
							    score += 10;
						    } else {
							    int w_s, h_s, scale_inv;
							    calc_scale(obs_y, FENCE_W, FENCE_H, &w_s, &h_s, &scale_inv);
							    write_fence_slot(i, get_lane_x(fences[i].lane, obs_y, w_s), obs_y, w_s, h_s, scale_inv, 1);
							    
							    if (check_collision(player_lane, player_state, fences[i].lane, obs_y, w_s, h_s, fences[i].active)) {
								    game_state = GAME_STATE_GAMEOVER;
								    hdmi_ctrl->GAME_CTRL = GAME_STATE_GAMEOVER;
								    player_state = 3; // dead
							    }
						    }
					    }
					}

					// Airborne clover logic
					for (int i=0; i<3; i++) {
						if (!clovers[i].active && (rand() % 75) == 0) {
							int lane = rand() % NUM_LANES;
							int conflict = 0;
							for (int j=0; j<4; j++) {
								if (fences[j].active && fences[j].lane == lane && fences[j].y_fp < (HORIZON_Y + 35) * 256) conflict = 1;
							}
							if (!conflict) {
								clovers[i].lane = lane;
								clovers[i].y_fp = HORIZON_Y << 8;
								clovers[i].airborne = rand() & 1;
								clovers[i].active = 1;
							}
						}
					}

					for (int i=0; i<3; i++) {
						if (clovers[i].active) {
							clovers[i].y_fp += get_speed_fp(clovers[i].y_fp >> 8);
							int pwr_y = clovers[i].y_fp >> 8;
							int w_s, h_s, scale_inv;
							calc_scale(pwr_y, CLOVER_W, CLOVER_H, &w_s, &h_s, &scale_inv);
							int screen_y = clovers[i].airborne ? get_airborne_y(pwr_y, h_s) : pwr_y;
							if (screen_y >= 480) {
								clovers[i].active = 0;
								write_clover_slot(i, 0, 0, CLOVER_W, CLOVER_H, 256, 0);
							} else {
								write_clover_slot(i, get_lane_x(clovers[i].lane, pwr_y, w_s), screen_y, w_s, h_s, scale_inv, 1);

								if (check_powerup(player_lane, player_state, clovers[i].lane, pwr_y, w_s, h_s, clovers[i].active, clovers[i].airborne)) {
									score += 50;
									clovers[i].active = 0;
									write_clover_slot(i, 0, 0, CLOVER_W, CLOVER_H, 256, 0);
								}
							}
						}
					}

					if (game_state == GAME_STATE_PLAYING) {
						hdmi_ctrl->GAME_CTRL = GAME_STATE_PLAYING;
						hdmi_ctrl->PLAYER_X = current_x;
						hdmi_ctrl->PLAYER_Y = player_y;
						hdmi_ctrl->PLAYER_STATE = (1 << 2) | player_state; // bit 2 is player_visible
						hdmi_ctrl->SCORE = score;

						char score_str[32];
						sprintf(score_str, "Score: %d", score);
						textHDMIDrawColorText(score_str, 1, 0, 0, 15);
						printHex(score, 1);
					}
				} else if (game_state == GAME_STATE_GAMEOVER) {
					textHDMIDrawColorText("GAME OVER", 35, 12, 0, 12);
					char final_score[32];
					sprintf(final_score, "Final Score: %d", score);
					textHDMIDrawColorText(final_score, 32, 14, 0, 14);
					textHDMIDrawColorText("Press ENTER to restart", 29, 18, 0, 10);
					
					if (enter_edge || enter_now) {
						game_state = GAME_STATE_MENU;
						textHDMIColorClr();
						textHDMIDrawColorText("SUBWAY SURFERS", 33, 12, 0, 15);
						textHDMIDrawColorText("Press ENTER to start", 30, 16, 0, 10);
						hdmi_ctrl->GAME_CTRL = GAME_STATE_MENU;
						hdmi_ctrl->FENCE_VIS = 0;
						hdmi_ctrl->FENCE2_VIS = 0;
						hdmi_ctrl->FENCE3_VIS = 0;
						hdmi_ctrl->FENCE4_VIS = 0;
						hdmi_ctrl->CLOVER_VIS = 0;
						hdmi_ctrl->CLOVER2_VIS = 0;
						hdmi_ctrl->CLOVER3_VIS = 0;
					}
				}

				for (int i = 0; i < 6; i++) {
					prev_kbdbuf.keycode[i] = kbdbuf.keycode[i];
				}
				prev_kbdbuf.mod = kbdbuf.mod;
				prev_kbdbuf.reserved = kbdbuf.reserved;

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
