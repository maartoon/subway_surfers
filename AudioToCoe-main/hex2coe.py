import sys

def raw_to_coe(input_file, output_file):
    # Read the raw hex file
    with open(input_file, 'rb') as raw_file:
        binary_data = raw_file.read()

    # Convert binary data to hexadecimal
    hex_data = binary_data.hex()

    # Ensure hex_data is 1024 * 4 characters long (256 words of 16 bits each)
    # If hex_data is shorter, pad it with zeros
    required_length = 2048 * 4
    if len(hex_data) < required_length:
        hex_data = hex_data.ljust(required_length, '0')
    else:
        hex_data = hex_data[:required_length]

    # Format the hex data into .coe format
    coe_content = "memory_initialization_radix=16;\nmemory_initialization_vector=\n"

    # Split the hex data into words (4 hex characters each for 16 bits)
    words = [hex_data[i:i+4] for i in range(0, len(hex_data), 4)]

    # Add words to the .coe content, ensuring correct depth
    coe_content += ",\n".join(words) + ";\n"

    # Write the .coe file
    with open(output_file, 'w') as coe_file:
        coe_file.write(coe_content)

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python3 file.py <input.raw> <output.coe>")
        sys.exit(1)

    input_file = sys.argv[1]
    output_file = sys.argv[2]

    raw_to_coe(input_file, output_file)
    print(f"Converted {input_file} to {output_file} successfully.")
