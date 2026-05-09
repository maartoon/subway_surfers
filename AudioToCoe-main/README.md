# AudioToCoe
This tool takes a binary RAW audio file (for example, exported from Audacity) and converts it into a .coe file that can be used in Xilinx Vivado memory initialization.
# Requirements
- Python 3.6+
- Audacity (to export the raw audio file)

# Step 1: Export RAW Audio from Audacity
1. Open your desired audio file in Audacity.
2. (Optional) Convert stereo to mono:
  Tracks → Mix → Mix Stereo Down to Mono
3. Export as RAW data:
- Go to **File → Export → Export Audio...**
- Under **Save as type**, choose **Other uncompressed files**
- Click **Options...**
  - **Header:** RAW (header-less)
  - **Encoding:** Signed 16-bit PCM
- Save the file

# Step 2: Convert RAW to COE
Once you have the `.raw` file, use the Python script to generate the `.coe` file.

# Usage
python3 raw_to_coe.py <input.raw> <output.coe>

# Notes
- Make sure the audio’s bit depth and endian format match your FPGA design (commonly 16-bit little-endian).
- If the audio file is too short, the script will pad with zeros.
- If the audio file is too long, it will truncate to fit the memory depth.
- There are example waveforms and outputs in the Example Waveforms Folder
