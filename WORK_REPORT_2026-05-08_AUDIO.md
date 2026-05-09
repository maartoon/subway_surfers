# Subway Surfers FPGA Audio Work Report (2026-05-08)

## Overview

This report summarizes the audio playback work completed for the `subway_surfers` FPGA project.

Primary objective:
- Play a COE-backed sound when the sheep jumps.
- Add a second crash sound using a separate 16-bit, 2048-depth BROM.
- Route the generated one-bit audio signal to the Urbana board audio output path.

Result:
- Hardware audio playback logic was added in SystemVerilog.
- Jump and crash sounds are triggered by hardware-visible game state changes.
- `audio_pwm` and `audio_sd` top-level ports were added for the Urbana audio output.
- Vivado integration/debug steps were identified for packaging, constraints, and ILA probing.

---

## Completed

## 1) Jump audio playback added

Updated:
- `final_project/design_source/jump_audio_player.sv`
- `final_project/design_source/jump_sound_rom.sv`
- `final_project/design_source/meh/meh.coe`
- `final_project/design_source/hdmi_text_controller_v1_0.sv`

Changes:
- Added a reusable sample playback module for 16-bit PCM samples.
- Added a simple ROM wrapper for `meh.coe` when not using Vivado-generated BROM IP.
- Connected jump audio to the existing hardware `PLAYER_STATE` register.
- Trigger behavior:
  - jump audio starts when `PLAYER_STATE` transitions into `PLAYER_JUMP`.
  - playback runs through 2048 samples.
  - retriggers are ignored while already playing.

Notes:
- The audio sample rate was changed from `22_050` Hz to `11_025` Hz after confirming the intended audio rate.

---

## 2) Crash audio playback added

Updated:
- `final_project/design_source/crash_sound_rom.sv`
- `final_project/design_source/crash/crash.coe`
- `final_project/design_source/hdmi_text_controller_v1_0.sv`

Changes:
- Added support for a second 16-bit, 2048-depth sound ROM named `crash_sound_rom`.
- Copied `AudioToCoe-main/crash.coe` into a project-local design source folder.
- Trigger behavior:
  - crash audio starts when `GAME_CTRL` transitions into `GAME_STATE_GAMEOVER`.
  - crash audio has priority over jump audio on the shared output.

Reason for using `GAME_CTRL`:
- Software sets `player_state = 3` on death, but the HDL currently reads only `game_regs[3][1:0]`.
- `GAME_STATE_GAMEOVER` is the reliable hardware-visible crash event.

---

## 3) Shared one-bit audio output added

Updated:
- `final_project/design_source/hdmi_text_controller_v1_0.sv`
- `final_project/nonip_design_src/mb_intro_top.sv`

Changes:
- Added `audio_pwm` output from the HDMI/game controller IP.
- Added `audio_pwm` top-level output to `mb_intro_top.sv`.
- Added `audio_sd` top-level output and tied it high:
  - `assign audio_sd = 1'b1;`
- Audio output uses a pulse-density style accumulator for one-bit output.

Board integration:
- `audio_pwm` should be constrained to the Urbana audio PWM pin.
- `audio_sd` should be constrained to the Urbana audio shutdown/enable pin.

Expected XDC audio section:

```tcl
set_property -dict { PACKAGE_PIN A11 IOSTANDARD LVCMOS33 } [get_ports {audio_pwm}]
set_property -dict { PACKAGE_PIN D12 IOSTANDARD LVCMOS33 } [get_ports {audio_sd}]
```

Removed/flagged bad XDC line:

```tcl
set_property PACKAGE_PIN <PIN_NAME> [get_ports audio_pwm]
```

---

## 4) Vivado packaging and debug guidance

Important findings:
- The HDMI controller is packaged as custom IP inside the block design.
- Adding `jump_audio_player.sv` only to top-level project sources is not enough if the packaged IP cannot see it.
- `jump_audio_player.sv` must be included in the HDMI controller IP package file group, or the packaged IP must otherwise reference it.
- If Vivado-generated BROM IPs named `jump_sound_rom` and `crash_sound_rom` already exist, do not also import same-name wrapper `.sv` files.

Block design requirements:
- The HDMI controller IP `audio_pwm` pin must be made external in `mb_block`.
- The external block design port should be named exactly `audio_pwm`.
- `audio_sd` does not need to be in the block design because it is tied high in `mb_intro_top.sv`.

Top-level checks:
- `get_ports *audio*` should return:
  - `audio_pwm`
  - `audio_sd`
- Pin checks should return:
  - `audio_pwm`: `A11`, `LVCMOS33`
  - `audio_sd`: `D12`, `LVCMOS33`

---

## 5) Verification limitations

Local verification attempted:
- Searched source tree for audio signal wiring and port references.
- Checked for available HDL tools.

Not available in the local shell:
- `iverilog`
- `verilator`
- `vivado`
- `xvlog`
- `xelab`
- `xsim`

Therefore, no HDL simulation was run locally.

Recommended next debug:
- Add an ILA probe for:
  - `audio_pwm`
  - `audio_sd`
  - `selected_audio_active`
  - `jump_audio_trigger`
  - `crash_audio_trigger`
  - `jump_sample_addr`
  - `crash_sample_addr`
- Trigger on `jump_audio_trigger == 1` or `selected_audio_active == 1`.
- Confirm sample addresses count and `audio_pwm` toggles.

---

## Current Audio Architecture

Audio playback is hardware controlled.

MicroBlaze role:
- Updates existing game registers such as `GAME_CTRL` and `PLAYER_STATE`.

Hardware role:
- Detects jump/game-over transitions.
- Reads samples from `jump_sound_rom` and `crash_sound_rom`.
- Generates `audio_pwm`.
- Keeps `audio_sd` high to enable the audio output circuit.

Vitis rebuild alone does not update audio HDL. Audio HDL changes require a regenerated bitstream and FPGA reprogramming.

