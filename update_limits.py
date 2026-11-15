import os
import re

file_path = "/Users/nathanbangwa243/Library/Application Support/Google/AndroidStudio2026.1.4/options/ai.providers.xml"

with open(file_path, "r", encoding="utf-8") as f:
    lines = f.readlines()

new_lines = []
in_block = False
block_lines = []

for line in lines:
    if "<ModelDetails>" in line:
        in_block = True
        block_lines = [line]
    elif "</ModelDetails>" in line:
        if in_block:
            block_lines.append(line)
            
            # Check if this ModelDetails is enabled
            is_enabled = any('name="enabled" value="true"' in l for l in block_lines)
            
            if is_enabled:
                for i in range(len(block_lines)):
                    if 'name="inputTokenLimit"' in block_lines[i]:
                        block_lines[i] = re.sub(r'value="[^"]+"', 'value="32768"', block_lines[i])
                    elif 'name="outputTokenLimit"' in block_lines[i]:
                        block_lines[i] = re.sub(r'value="[^"]+"', 'value="8192"', block_lines[i])
            
            new_lines.extend(block_lines)
        else:
            new_lines.append(line)
        in_block = False
    else:
        if in_block:
            block_lines.append(line)
        else:
            new_lines.append(line)

with open(file_path, "w", encoding="utf-8") as f:
    f.writelines(new_lines)

print("Updated limits for enabled models.")
