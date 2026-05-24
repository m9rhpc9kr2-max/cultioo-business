#!/usr/bin/env python3
"""
Final fix: Remove const from all widget constructors
"""

import os
import re
from pathlib import Path

lib_path = Path(".") / "lib"
fixed = 0

for root, dirs, files in os.walk(lib_path):
    for file in files:
        if file.endswith(".dart"):
            file_path = Path(root) / file
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()
            
            original = content
            
            # Remove const from all widget constructors
            content = re.sub(r'const\s+TextStyle\s*\(', 'TextStyle(', content)
            content = re.sub(r'const\s+Text\s*\(', 'Text(', content)
            content = re.sub(r'const\s+SizedBox\s*\(', 'SizedBox(', content)
            content = re.sub(r'const\s+Container\s*\(', 'Container(', content)
            content = re.sub(r'const\s+BoxDecoration\s*\(', 'BoxDecoration(', content)
            content = re.sub(r'const\s+Padding\s*\(', 'Padding(', content)
            content = re.sub(r'const\s+ClipRRect\s*\(', 'ClipRRect(', content)
            content = re.sub(r'const\s+Row\s*\(', 'Row(', content)
            content = re.sub(r'const\s+Column\s*\(', 'Column(', content)
            content = re.sub(r'const\s+Icon\s*\(', 'Icon(', content)
            content = re.sub(r'const\s+EdgeInsets\.', 'EdgeInsets.', content)
            content = re.sub(r'const\s+BorderRadius\.', 'BorderRadius.', content)
            
            if content != original:
                with open(file_path, 'w', encoding='utf-8') as f:
                    f.write(content)
                fixed += 1
                print(f"✅ {file_path.relative_to('.')}")

print(f"\n✅ Fixed {fixed} files")
