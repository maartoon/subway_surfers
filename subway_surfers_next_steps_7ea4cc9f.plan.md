---
name: Subway Surfers Next Steps
overview: A three-step plan to add USB keyboard control, scrolling background with obstacles/power-ups, and a respawn/game-over loop to the Subway Surfers FPGA game, followed by a roadmap for 2.5D perspective and polish.
todos:
  - id: step1-axi-regs
    content: "Step 1A: Add game state registers (0x80C-0x816) to hdmi_text_controller_v1_0_AXI.sv with read/write logic"
    status: pending
  - id: step1-wire-regs
    content: "Step 1B: Wire game_regs to hdmi_text_controller_v1_0.sv, replace hardcoded localparams with register-backed positions, and add player state sprite selection logic"
    status: pending
  - id: step1-sw-header
    content: "Step 1C: Update hdmi_text_controller.h struct to include game register fields and game defines"
    status: pending
  - id: step1-game-loop
    content: "Step 1D: Rewrite lw_usb_main.c with game loop integrating USB keyboard polling, lane movement, jump/duck, and AXI register writes"
    status: pending
  - id: step2-bg-scroll
    content: "Step 2A: Enhance Color_Mapper.sv background with animated grass stripes and scrolling ground lines"
    status: pending
  - id: step2-obstacle-sw
    content: "Step 2B: Add obstacle/power-up spawn, move, and despawn logic in software with perspective-correct X positioning"
    status: pending
  - id: step2-obstacle-hw
    content: "Step 2C: Verify hardware active-gating for fence/clover sprites; optionally add multiple obstacle ROM instances"
    status: pending
  - id: step3-collision
    content: "Step 3A: Implement lane-based collision detection in software (jump clears ground obstacles, duck clears high obstacles)"
    status: pending
  - id: step3-fsm
    content: "Step 3B: Implement MENU -> PLAYING -> GAMEOVER state machine with VRAM text overlays for UI"
    status: pending
  - id: step3-score
    content: "Step 3C: Display score on VRAM text layer and HEX displays; add screen dimming on game over"
    status: pending
isProject: false
---


# Subway Surfers FPGA -- Next Steps Implementation Plan

## Current State Summary

The project has:
- A MicroBlaze SoC with HDMI output via a custom AXI4-Lite IP (`hdmi_text_controller`)
- Sprite ROMs for **fence** (obstacle), **clover** (power-up), **moon** (decoration), **sheep1/sheep2** (player run animation), **sheepj1** (player jump)
- A **color mapper** with a 2.5D perspective background: sky gradient + stars, grass, a 3-lane converging road with animated dashed lane markers
- All sprite positions are **hardcoded as `localparam`** in [hdmi_text_controller_v1_0.sv](final_project/design_source/hdmi_text_controller_v1_0.sv) (lines 110-115)
- USB keyboard driver code exists in [software/lw_usb/](final_project/software/lw_usb/) and [lw_usb_main.c](final_project/software/lw_usb_main.c) but only prints keycodes to UART -- no game logic

**Key architectural principle (from the proposal):** Software (MicroBlaze C code) handles all game logic (keyboard, game state, collision, spawning). Hardware (SystemVerilog) only handles rendering. They communicate through **AXI-mapped registers**.

---

## Step 1: USB Keyboard Control of the Player Sprite

### Goal
Read keyboard input via the existing USB/SPI stack and translate it into player lane movement (left/right) and actions (jump/duck), writing sprite positions to new AXI registers that the hardware uses for rendering.

### 1A. Add Game State Registers to the AXI Slave

**File:** [hdmi_text_controller_v1_0_AXI.sv](final_project/design_source/hdmi_text_controller_v1_0_AXI.sv)

Add a new bank of writable 32-bit registers for game state, starting at **word address 0x80C** (byte address 0x2030), after the existing read-only sync registers (0x808-0x80A). Define 11 new registers:

| Word Addr | Byte Addr | Name | Description |
|---|---|---|---|
| 0x80C | 0x2030 | `GAME_CTRL` | `{28'b0, game_state[3:0]}` -- 0=menu, 1=playing, 2=gameover |
| 0x80D | 0x2034 | `PLAYER_X` | `{22'b0, x[9:0]}` -- player sprite X |
| 0x80E | 0x2038 | `PLAYER_Y` | `{22'b0, y[9:0]}` -- player sprite Y |
| 0x80F | 0x203C | `PLAYER_STATE` | `{30'b0, state[1:0]}` -- 0=run, 1=jump, 2=duck |
| 0x810 | 0x2040 | `FENCE_X` | `{22'b0, x[9:0]}` -- obstacle X |
| 0x811 | 0x2044 | `FENCE_Y` | `{22'b0, y[9:0]}` -- obstacle Y |
| 0x812 | 0x2048 | `FENCE_VIS` | `{31'b0, visible[0]}` -- obstacle active/visible |
| 0x813 | 0x204C | `CLOVER_X` | `{22'b0, x[9:0]}` -- power-up X |
| 0x814 | 0x2050 | `CLOVER_Y` | `{22'b0, y[9:0]}` -- power-up Y |
| 0x815 | 0x2054 | `CLOVER_VIS` | `{31'b0, visible[0]}` -- power-up active/visible |
| 0x816 | 0x2058 | `SCORE` | `{16'b0, score[15:0]}` |

**Implementation in `hdmi_text_controller_v1_0_AXI.sv`:**

1. **Declare a new register array** for game state:
```systemverilog
logic [C_S_AXI_DATA_WIDTH-1:0] game_regs [11]; // 0x80C..0x816
```

2. **Add an output port** to expose game_regs to the parent module:
```systemverilog
output logic [C_S_AXI_DATA_WIDTH-1:0] game_regs [11]
```

3. **Add write logic** (similar to the existing `color_regs` write block, around line 515):
```systemverilog
always_ff @(posedge S_AXI_ACLK) begin
  if (S_AXI_ARESETN == 1'b0) begin
    for (int i = 0; i < 11; i++) game_regs[i] <= 32'b0;
  end else begin
    if (slv_reg_wren && axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] >= 12'h80C
        && axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] <= 12'h816) begin
      for (byte_index = 0; byte_index <= 3; byte_index = byte_index+1) begin
        if (S_AXI_WSTRB[byte_index] == 1) begin
          game_regs[axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] - 12'h80C][(byte_index*8) +: 8]
            <= S_AXI_WDATA[(byte_index*8) +: 8];
        end
      end
    end
  end
end
```

4. **Add read logic** in the existing `always_comb` block (around line 430) -- extend the `case` statement:
```systemverilog
12'h80C: reg_data_out = game_regs[0];
12'h80D: reg_data_out = game_regs[1];
// ... through 0x816 => game_regs[10]
```

**CAUTION:** The `axi_rdata` assignment (line 455-479) uses `axi_araddr[13]` to distinguish BRAM vs registers. Word addresses 0x80C-0x816 have bit 13 == 0 and bit 11 == 1. Make sure the condition routes to `reg_data_out` for all addresses >= 0x800, not just those where bit 13 is set. The existing code checks `axi_araddr[13] == 1'b1` but 0x80C in word-address has bit 11 set. The actual byte address for 0x80C is 0x2030, and `axi_araddr[13]` of 0x2030 is 1. So the existing check should work, but verify by tracing the address bits carefully.

### 1B. Wire Game Registers to the Rendering Module

**File:** [hdmi_text_controller_v1_0.sv](final_project/design_source/hdmi_text_controller_v1_0.sv)

1. **Add a `game_regs` wire** and connect it to the AXI instance port list (around line 118):
```systemverilog
logic [31:0] game_regs [11];
```
Then add `.game_regs(game_regs)` to the `hdmi_text_controller_v1_0_AXI` instantiation.

2. **Replace hardcoded localparams** for the player and obstacle sprites with register-backed signals:
```systemverilog
// Player position from software
wire [9:0] sheep_pos_x = game_regs[1][9:0];  // PLAYER_X
wire [9:0] sheep_pos_y = game_regs[2][9:0];  // PLAYER_Y
wire [1:0] player_state = game_regs[3][1:0];  // PLAYER_STATE

// Obstacle position from software
wire [9:0] fence_pos_x = game_regs[4][9:0];  // FENCE_X
wire [9:0] fence_pos_y = game_regs[5][9:0];  // FENCE_Y
wire       fence_active = game_regs[6][0];     // FENCE_VIS

// Power-up position from software
wire [9:0] clover_pos_x = game_regs[7][9:0];  // CLOVER_X
wire [9:0] clover_pos_y = game_regs[8][9:0];  // CLOVER_Y
wire       clover_active = game_regs[9][0];     // CLOVER_VIS
```

3. **Update the `always_comb` block** (around line 206) that computes `*_inrange` and `local_x/y_*`:
   - Replace `SHEEP1_X` / `SHEEP1_Y` with `sheep_pos_x` / `sheep_pos_y` (same for SHEEP2 and SHEEPJ1 -- they all share the player position)
   - Replace `FENCE_X` / `FENCE_Y` with `fence_pos_x` / `fence_pos_y`
   - Replace `CLOVER_X` / `CLOVER_Y` with `clover_pos_x` / `clover_pos_y`
   - Add active-gating: fence_inrange should also require `fence_active`, clover_inrange should require `clover_active`

4. **Handle player state for sprite selection:**
   - When `player_state == 0` (running): show sheep1/sheep2 animation at player position, hide sheepj1
   - When `player_state == 1` (jumping): show sheepj1 at player position, hide sheep1/sheep2
   - When `player_state == 2` (ducking): show sheep1/sheep2 at player position (collision box changes in software, not rendering)

   Modify the `sheep1_valid`/`sheep2_valid`/`sheepj1_valid` assignments (around line 241):
```systemverilog
assign sheep1_valid = sheep1_inrange_d && ~sheep_use_frame2
                      && (player_state != 2'd1) && (sheep1_idx != 1);
assign sheep2_valid = sheep2_inrange_d && sheep_use_frame2
                      && (player_state != 2'd1) && (sheep2_idx != 3);
assign sheepj1_valid = sheepj1_inrange_d && (player_state == 2'd1)
                       && (sheep_j1_idx != 0);
```

### 1C. Update the Software Header for Game Registers

**File:** [hdmi_text_controller.h](final_project/software/hdmi_text_controller.h)

Extend the `TEXT_HDMI_STRUCT` to include game registers. After the existing `DRAWY` field, add padding and then the game registers:

```c
struct TEXT_HDMI_STRUCT {
    uint8_t  VRAM[ROWS*COLUMNS*2];
    uint8_t  PAD[0x2000 - ROWS*COLUMNS*2];
    uint32_t PALETTE[8];
    uint32_t FRAME_COUNT;
    uint32_t DRAWX;
    uint32_t DRAWY;
    uint32_t _reserved;     // 0x80B padding
    uint32_t GAME_CTRL;     // 0x80C
    uint32_t PLAYER_X;      // 0x80D
    uint32_t PLAYER_Y;      // 0x80E
    uint32_t PLAYER_STATE;  // 0x80F
    uint32_t FENCE_X;       // 0x810
    uint32_t FENCE_Y;       // 0x811
    uint32_t FENCE_VIS;     // 0x812
    uint32_t CLOVER_X;      // 0x813
    uint32_t CLOVER_Y;      // 0x814
    uint32_t CLOVER_VIS;    // 0x815
    uint32_t SCORE;         // 0x816
};
```

Also add game-related defines:

```c
#define GAME_STATE_MENU     0
#define GAME_STATE_PLAYING  1
#define GAME_STATE_GAMEOVER 2

#define PLAYER_RUN  0
#define PLAYER_JUMP 1
#define PLAYER_DUCK 2

#define HORIZON_Y   220
#define PLAYER_BASE_Y 380
#define SPRITE_W    40
#define SPRITE_H    50

#define NUM_LANES   3
```

### 1D. Implement the Game Loop with Keyboard Input

**File:** [lw_usb_main.c](final_project/software/lw_usb_main.c)

This is the most substantial software change. Restructure `main()` to include a game loop.

**Key USB HID keycodes** (from the PDF, page 10):
- `0x04` = A (move left)
- `0x07` = D (move right)
- `0x1A` = W (jump)
- `0x16` = S (duck)
- `0x50` = Left Arrow (move left)
- `0x4F` = Right Arrow (move right)
- `0x52` = Up Arrow (jump)
- `0x51` = Down Arrow (duck)
- `0x28` = Enter (start/restart)
- `0x29` = Escape (return to menu)

**Lane X-position computation** (must match the hardware's perspective math in [Color_Mapper.sv](final_project/design_source/Color_Mapper.sv), lines 156-180):

```c
int get_lane_x(int lane, int y_pos) {
    int row_depth = y_pos - HORIZON_Y;
    int road_half_width = 48 + (row_depth >> 1);
    int road_left = 320 - road_half_width;
    int lane_width = (road_half_width * 2) / 3;
    return road_left + lane * lane_width + (lane_width / 2) - (SPRITE_W / 2);
}
```

**Main game loop structure:**

```c
int main() {
    // ... existing USB init code ...
    
    // Game state
    int player_lane = 1;  // 0=left, 1=center, 2=right
    int player_state = PLAYER_RUN;
    int jump_timer = 0;
    int game_state = GAME_STATE_MENU;
    int score = 0;
    BYTE prev_keycode = 0;
    
    // Initial palette setup
    for (int i = 0; i < 16; i++)
        setColorPalette(i, colors[i].red, colors[i].green, colors[i].blue);
    
    while (1) {
        MAX3421E_Task();
        USB_Task();
        
        if (GetUsbTaskState() == USB_STATE_RUNNING) {
            // ... existing driver init code ...
            
            BOOT_KBD_REPORT kbdbuf;
            BYTE rcode = kbdPoll(&kbdbuf);
            BYTE key = (rcode == 0) ? kbdbuf.keycode[0] : 0;
            
            // Edge detection: only trigger on new key press
            BYTE key_pressed = (key != prev_keycode && key != 0) ? key : 0;
            prev_keycode = key;
            
            // Process input based on game state
            if (game_state == GAME_STATE_PLAYING) {
                if ((key_pressed == 0x04 || key_pressed == 0x50) && player_lane > 0)
                    player_lane--;
                if ((key_pressed == 0x07 || key_pressed == 0x4F) && player_lane < 2)
                    player_lane++;
                if ((key_pressed == 0x1A || key_pressed == 0x52) && player_state == PLAYER_RUN) {
                    player_state = PLAYER_JUMP;
                    jump_timer = 30; // ~0.5 sec at 60fps
                }
                // ... duck on S/Down held ...
                
                // Update jump timer
                if (player_state == PLAYER_JUMP) {
                    jump_timer--;
                    if (jump_timer <= 0) player_state = PLAYER_RUN;
                }
                
                // Write player position
                int px = get_lane_x(player_lane, PLAYER_BASE_Y);
                int py = PLAYER_BASE_Y;
                if (player_state == PLAYER_JUMP)
                    py -= 40; // jump height offset
                    
                hdmi_ctrl->PLAYER_X = px;
                hdmi_ctrl->PLAYER_Y = py;
                hdmi_ctrl->PLAYER_STATE = player_state;
            }
            
            sleepframe(1); // sync to VGA frame
        }
    }
}
```

**CAUTION areas for Step 1:**
- **Key debouncing:** USB HID reports are polled, not edge-triggered. You must track the previous keycode and only act on transitions (new key press), otherwise holding a key will trigger repeated lane changes every frame.
- **BRAM read latency:** The existing 1-cycle delay pipeline (lines 188-204 of `hdmi_text_controller_v1_0.sv`) already handles BRAM/ROM read latency. Game registers are combinational (no BRAM pipeline), so they don't need the delay -- but the sprite ROM lookups that use register-backed positions still go through the delayed pipeline, so this should work as-is.
- **Timing of writes:** The software should write all game registers before the next frame begins. Using `sleepframe(1)` at the end of the loop ensures writes happen during the blanking interval.
- **Top-level ports:** No changes to [mb_intro_top.sv](final_project/nonip_design_src/mb_intro_top.sv) are needed -- game registers are internal to the IP.

---

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
