import sys
import os

def extract_uart_lines(input_file_path, output_file_path, config=None, kernel=None):
    """
    Appends UART lines from input_file_path to output_file_path.
    Adds headers for each kernel and optional configuration label.
    """
    with open(input_file_path, 'r') as input_file:
        with open(output_file_path, 'a') as output_file:  # Append mode
            # Write spacing and header
            output_file.write("\n\n")
            if config:
                output_file.write(f"Configuration: {config}\n")
            if kernel:
                output_file.write(f"=== Kernel: {kernel} ===\n")
            output_file.write("----------------------------------------\n")

            # Copy only lines containing '[UART]'
            for line in input_file:
                if '[UART]' in line:
                    output_file.write(line)

            output_file.write("\n----------------------------------------\n")

if __name__ == "__main__":
    argc = len(sys.argv)
    if argc == 3:
        input_file_path = sys.argv[1]
        output_file_path = sys.argv[2]
        extract_uart_lines(input_file_path, output_file_path)
    elif argc == 4:
        input_file_path = sys.argv[1]
        output_file_path = sys.argv[2]
        config = sys.argv[3]
        extract_uart_lines(input_file_path, output_file_path, config)
    elif argc == 5:
        input_file_path = sys.argv[1]
        output_file_path = sys.argv[2]
        config = sys.argv[3]
        kernel = sys.argv[4]
        extract_uart_lines(input_file_path, output_file_path, config, kernel)
    else:
        print("Usage: python3 write_results.py <input_log> <output_summary> [config] [kernel]")
