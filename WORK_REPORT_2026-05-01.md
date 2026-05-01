# Subway Surfers FPGA Work Report (2026-05-01)

## Overview

This report summarizes what was completed today for the `subway_surfers` project, what issues were debugged, and what remains for future work.

Primary objective today was Step 1 implementation and bring-up:
- Step 1A: AXI game control registers
- Step 1B: Hardware wiring for software-controlled sprite positions/states
- Step 1C: Software register map updates
- Step 1D: USB keyboard-driven game loop foundation

Result: Step 1 is implemented and system bring-up is now working (USB/SPI/UART path recovered; project reaches runtime state properly).

---

## Completed Today

## 1) Step 1A - AXI game register bank added

Updated:
- `final_project/design_source/hdmi_text_controller_v1_0_AXI.sv`

Changes:
- Added `game_regs[11]` output register bank.
- Added readable/writable game registers at word addresses:
  - `0x80C` .. `0x816`
- Added byte-strobe-aware write logic for game registers.
- Added readback decode for all game registers.
- Refactored address decode using explicit word-address helpers.

Purpose:
- Provide a clean hardware/software interface for game state and object positions.

---

## 2) Step 1B - Hardware rendering switched to register-driven game state

Updated:
- `final_project/design_source/hdmi_text_controller_v1_0.sv`

Changes:
- Wired through `game_regs` from AXI module.
- Replaced hardcoded player/fence/clover positions with software-controlled registers.
- Added visibility gating from `FENCE_VIS` / `CLOVER_VIS`.
- Added player visibility/state control from `GAME_CTRL` and `PLAYER_STATE`.
- Added jump sprite selection behavior (jump state uses jump sprite).

Purpose:
- Allow MicroBlaze game logic to drive rendering positions and animation state.

---

## 3) Step 1C - Software MMIO map and constants updated

Updated:
- `final_project/software/hdmi_text_controller.h`

Changes:
- Added gameplay constants:
  - game states, player states, lane/geometry constants.
- Extended `TEXT_HDMI_STRUCT` with game register fields:
  - `GAME_CTRL`, `PLAYER_X/Y/STATE`, `FENCE_X/Y/VIS`, `CLOVER_X/Y/VIS`, `SCORE`
- Added reserved alignment field around `0x80B`.
- Corrected base-address pointer cast style for MMIO struct pointer.

Purpose:
- Keep software view of AXI register map aligned with hardware.

---

## 4) Step 1D - Keyboard game loop foundation implemented

Updated:
- `final_project/software/lw_usb_main.c`

Changes:
- Added lane projection helper (`get_lane_x`) consistent with perspective road math.
- Added keyboard report parsing helpers.
- Added initialization for new game registers.
- Added initial menu text and Enter-to-start flow.
- Added player controls:
  - left/right lane shift
  - jump/duck states
- Added frame-based state updates and register writes to hardware.
- Added debug output and keycode-to-HEX forwarding.

Purpose:
- Establish software-side game loop control for Step 1 requirements.

---

## Major Debugging and Bring-Up Issues Resolved

## A) UART no output (critical)

Issue:
- No terminal output initially.

Root cause:
- UART RX/TX were cross-wired in top-level wrapper.

Fix:
- Corrected UART mapping in:
  - `final_project/nonip_design_src/mb_intro_top.sv`

---

## B) USB SPI link dead (`MAX3421E revision reads: 0 0 0 0`)

Issue:
- MAX3421E was not responding over SPI; reset timed out.

Key contributors identified and corrected:
- Top-level did not expose/wire USB SPI and control pins correctly for active build.
- Vector/scalar consistency issues around USB-related ports (especially `[0:0]` style signals).
- Additional diagnostics added for SPI select/readback and reset behavior.

Fixes:
- Updated top-level to expose and connect USB pins through `mb_block`:
  - `gpio_usb_int_tri_i[0]`
  - `gpio_usb_rst_tri_o[0]`
  - `usb_spi_miso`, `usb_spi_mosi`, `usb_spi_sclk`, `usb_spi_ss[0]`
- File:
  - `final_project/nonip_design_src/mb_intro_top.sv`

---

## C) Misleading USB interrupt behavior

Issue:
- Repeated `IRQ: 0` / false interrupt behavior during bring-up.

Fixes:
- Corrected GPIO direction setup for USB interrupt input.
- Tightened interrupt handling and added diagnostics.
- Added safer SPI health gating and clear failure reporting.

Updated:
- `final_project/software/lw_usb/MAX3421E.c`

---

## Current Status at End of Session

- Step 1 infrastructure has been implemented in hardware/software.
- UART and USB/SPI path have been brought back to working state.
- System now runs beyond earlier bring-up blockers.
- Remaining gameplay features (Steps 2 and 3) are not yet implemented.

---

## What Still Needs To Be Done

## Step 2: Background Scrolling and Obstacle / Power-Up Generation

### Goal
Make the background scroll convincingly, spawn fence obstacles and clover power-ups at random lanes near the horizon, and move them toward the player.

### 2A. Enhance Background Scrolling

**File:** [Color_Mapper.sv](final_project/design_source/Color_Mapper.sv)

The dashed lane markers already scroll (line 178: `dash_phase = DrawY[5:0] - frame_count[6:1]`). To complete the scrolling illusion:

1. **Animate the grass stripes** to scroll toward the camera. Currently the grass alternates based on `DrawY[6]` (static bands). Change this to use `frame_count` for downward motion:
```systemverilog
logic [5:0] grass_phase;
assign grass_phase = DrawY[5:0] + frame_count[4:0];
// Use grass_phase[5] instead of DrawY[6] for grass band selection
```

2. **Animate the horizon blend** subtly to give a sense of forward motion (optional polish).

3. **Add horizontal ground lines** that get thicker as they approach the camera (per the proposal's "black/dark green horizontal lines that increase thickness as they move down the screen"):
```systemverilog
logic ground_line_on;
logic [9:0] ground_line_phase;
assign ground_line_phase = (DrawY + frame_count[5:0]) & 10'h03F; // period ~64 pixels
assign ground_line_on = (DrawY > HORIZON_Y) && (ground_line_phase < (row_depth >> 4));
```
When `ground_line_on`, darken the grass color slightly.

### 2B. Obstacle and Power-Up Lifecycle in Software

**File:** [lw_usb_main.c](final_project/software/lw_usb_main.c)

Add obstacle management to the game loop:

```c
// Obstacle state
int obs_lane = -1;
int obs_y = 0;
int obs_active = 0;
int obs_speed = 2;

// Power-up state
int pwr_lane = -1;
int pwr_y = 0;
int pwr_active = 0;

// In the game loop (each frame):
if (game_state == GAME_STATE_PLAYING) {
    // Spawn new obstacle if none active
    if (!obs_active) {
        obs_lane = rand() % 3;
        obs_y = HORIZON_Y + 5;  // start just below horizon
        obs_active = 1;
    }
    
    // Move obstacle toward player
    obs_y += obs_speed;
    if (obs_y > 480) {
        obs_active = 0;  // off screen, despawn
        score++;
    }
    
    // Compute perspective-correct X for obstacle
    int obs_x = get_lane_x(obs_lane, obs_y);
    
    // Write obstacle position to hardware
    hdmi_ctrl->FENCE_X = obs_x;
    hdmi_ctrl->FENCE_Y = obs_y;
    hdmi_ctrl->FENCE_VIS = obs_active;
    
    // Similar logic for clover power-up (less frequent)
    // ...
    
    hdmi_ctrl->SCORE = score;
}
```

**Randomness:** Use `rand()` seeded with the frame counter at game start (`srand(hdmi_ctrl->FRAME_COUNT)`). This provides pseudo-random obstacle placement.

**Speed scaling:** Increase `obs_speed` over time or as score increases to raise difficulty.

### 2C. Update Hardware for Dynamic Obstacle Rendering

The changes from Step 1B already handle dynamic fence and clover positions. Additional tweaks needed:

**File:** [hdmi_text_controller_v1_0.sv](final_project/design_source/hdmi_text_controller_v1_0.sv)

- When `fence_active == 0`, force `fence_inrange = 0` so the sprite is hidden
- When `clover_active == 0`, force `clover_inrange = 0`

This should already be handled by the Step 1B modifications. Verify that the gating logic works:
```systemverilog
fence_inrange = fence_active && (drawX >= fence_pos_x) && ...;
clover_inrange = clover_active && (drawX >= clover_pos_x) && ...;
```

### 2D. (Optional) Multiple Simultaneous Obstacles

To have more than 1 obstacle on screen simultaneously, you have two options:

**Option A (Recommended for simplicity):** Duplicate the fence ROM instance in `hdmi_text_controller_v1_0.sv`. Add `fence2_rom` and `fence3_rom` instances using the same `.coe` file, each with their own address/index signals, position registers (add more game_regs: `FENCE2_X/Y/VIS`, `FENCE3_X/Y/VIS`), and corresponding valid/color signals wired into the color mapper. This costs more BRAM but is straightforward.

**Option B (Resource-efficient):** Time-multiplex a single ROM by computing addresses for all obstacle slots and selecting the correct output based on which slot overlaps the current pixel. This is more complex but saves BRAM.

For the initial implementation, **start with a single obstacle**. Add more once the core loop works.

**CAUTION areas for Step 2:**
- **Perspective X computation:** The obstacle X position MUST use the same lane math as the color mapper's road drawing (lines 164-170 in `Color_Mapper.sv`). If these don't match, obstacles will appear to float off the road. Use `get_lane_x()` in the software which mirrors the hardware formula.
- **Sprite size vs depth:** At this stage, sprites are rendered at their native pixel size regardless of Y depth. This means a fence at the horizon looks the same size as one near the player. This will be fixed in the 2.5D perspective step (Week 3 of the proposal). For now, this is acceptable.
- **Frame synchronization:** Always update ALL game registers in one batch before calling `sleepframe(1)`. Partial updates mid-frame can cause visual tearing or glitches.

---

## Step 3: Game State Machine and Respawn Loop

### Goal
Implement a complete game loop: Menu -> Playing -> Game Over -> Restart, with collision detection and score display.

### 3A. Collision Detection in Software

**File:** [lw_usb_main.c](final_project/software/lw_usb_main.c)

Collision is checked in the software each frame. Since the game is lane-based, collision is simple:

```c
int check_collision(int player_lane, int player_state,
                    int obs_lane, int obs_y, int obs_active) {
    if (!obs_active) return 0;
    
    // Obstacle is in collision range when it overlaps the player's Y band
    int player_y_top = PLAYER_BASE_Y;
    int player_y_bot = PLAYER_BASE_Y + SPRITE_H;
    
    if (player_state == PLAYER_JUMP)
        player_y_top -= 40;  // jumping raises the player
    
    int obs_top = obs_y;
    int obs_bot = obs_y + SPRITE_H;
    
    // Check lane match AND vertical overlap
    if (player_lane == obs_lane &&
        obs_bot >= player_y_top && obs_top <= player_y_bot) {
        // Jumping clears ground obstacles
        if (player_state == PLAYER_JUMP) return 0;
        return 1;  // collision!
    }
    return 0;
}
```

**Per the proposal:** "jumping ignores ground barriers, ducking ignores high barriers, colliding ends the game." You can extend this by adding an obstacle type field and implementing different collision rules per type.

### 3B. Game State FSM in Software

**File:** [lw_usb_main.c](final_project/software/lw_usb_main.c)

```c
switch (game_state) {
    case GAME_STATE_MENU:
        // Display "SUBWAY SURFERS" and "Press ENTER to start" using VRAM text
        textHDMIDrawColorText("SUBWAY SURFERS", 33, 12, 0, 15);
        textHDMIDrawColorText("Press ENTER to start", 30, 16, 0, 10);
        
        // Hide all game sprites
        hdmi_ctrl->FENCE_VIS = 0;
        hdmi_ctrl->CLOVER_VIS = 0;
        
        if (key_pressed == 0x28) { // Enter
            game_state = GAME_STATE_PLAYING;
            textHDMIColorClr();
            player_lane = 1;
            score = 0;
            obs_active = 0;
            srand(hdmi_ctrl->FRAME_COUNT);
        }
        break;
        
    case GAME_STATE_PLAYING:
        // ... keyboard + obstacle + collision logic from Steps 1 and 2 ...
        
        if (check_collision(...)) {
            game_state = GAME_STATE_GAMEOVER;
            hdmi_ctrl->PLAYER_STATE = 3; // dead state (optional animation)
        }
        
        // Draw score as text overlay
        char score_str[20];
        sprintf(score_str, "Score: %d", score);
        textHDMIDrawColorText(score_str, 1, 0, 0, 15); // top-left corner
        break;
        
    case GAME_STATE_GAMEOVER:
        textHDMIDrawColorText("GAME OVER", 35, 12, 0, 12);
        char final_score[30];
        sprintf(final_score, "Final Score: %d", score);
        textHDMIDrawColorText(final_score, 32, 14, 0, 14);
        textHDMIDrawColorText("Press ENTER to restart", 29, 18, 0, 10);
        
        if (key_pressed == 0x28) { // Enter
            game_state = GAME_STATE_MENU;
            textHDMIColorClr();
        }
        break;
}
```

### 3C. Score Display via HEX Displays

Use the existing `printHex()` function and `gpio_usb_keycode` GPIO to display the score on the physical hex displays as a nice secondary indicator:

```c
printHex(score, 1);
```

### 3D. Wire GAME_CTRL Register to Hardware (Optional Visual Feedback)

The `GAME_CTRL` register (game_regs[0]) can be read by the color mapper to change the background during different game states. For example, darken the screen on game over:

**File:** [Color_Mapper.sv](final_project/design_source/Color_Mapper.sv)

Add a `game_state` input port and apply a dim filter when `game_state == GAME_STATE_GAMEOVER`:
```systemverilog
if (game_state == 2) begin
    Red   = Red >> 1;
    Green = Green >> 1;
    Blue  = Blue >> 1;
end
```

**CAUTION areas for Step 3:**
- **Text rendering over the game:** The VRAM text layer is rendered by the color mapper (lines 234-238 in `Color_Mapper.sv`) when `code_n != 0 && is_foreground`. Score/UI text will appear over the background but UNDER sprites (due to priority ordering). This is the correct behavior -- sprites should be in front of text.
- **Clearing text between states:** Always call `textHDMIColorClr()` when transitioning between states to avoid leftover text from the previous screen.
- **`sprintf` memory usage:** `sprintf` uses significant stack space with the full `printf` library. If you reduced MicroBlaze on-chip memory below 128KB, use `xil_printf` (no `%d` formatting) and manual integer-to-string conversion instead.
- **Collision timing:** Check collision AFTER moving the obstacle but BEFORE despawning it. This prevents obstacles from passing through the player on the frame they exit the screen.

---

## After These Three Steps: Completing the Project

Per the **Week 3** goal in the proposal, the next major feature is **2.5D perspective scaling**:

1. **Sprite Scaler Module:** Create a hardware module that reads the sprite ROM and scales the output based on a `depth` parameter derived from the sprite's Y position. Use a LUT that maps Y distance from the horizon to a scale factor (e.g., 0.25x at Y=230, 0.5x at Y=300, 0.75x at Y=370, 1.0x at Y=440).

2. **Depth-Based Rendering:** Replace the fixed `SPRITE_W`/`SPRITE_H` with scaled dimensions. The `*_inrange` computation becomes: `scaled_w = base_w * scale_factor; scaled_h = base_h * scale_factor`. The ROM address computation must account for the scale factor (skip pixels to shrink, duplicate to enlarge).

3. **Z-Ordering:** Sprites closer to the camera (larger Y) should render on top of sprites farther away. The current priority-based rendering in the color mapper can be extended by sorting sprites by Y before assigning priorities.

Per **Week 4** (polish and reach goals):
- **Main menu / ending screen** (partially done in Step 3)
- **High score persistence** (store in BRAM or a register that persists between game sessions)
- **Sound effects** (requires additional hardware: PWM output or audio DAC)
- **Increased obstacle variety** (add more sprite ROMs, or use the text system for simple obstacles)
- **Difficulty progression** (increase obstacle speed and spawn rate over time)

## Recommended Next Session Plan

1. Implement Step 2 obstacle/power-up lifecycle first in software.
2. Validate register writes on screen before tuning behavior.
3. Add collision and Game Over flow (Step 3).
4. Refine input handling and balancing (speed, spawn cadence).
5. Final cleanup and demo script.

---

## Files Touched Today

- `final_project/design_source/hdmi_text_controller_v1_0_AXI.sv`
- `final_project/design_source/hdmi_text_controller_v1_0.sv`
- `final_project/software/hdmi_text_controller.h`
- `final_project/software/lw_usb_main.c`
- `final_project/software/lw_usb/MAX3421E.c`
- `final_project/nonip_design_src/mb_intro_top.sv`

---

## Notes

- The USB/SPI bring-up was the main blocker and consumed most debugging time.
- With that now fixed, Steps 2 and 3 are straightforward software-driven extensions on top of the new AXI game register interface.
