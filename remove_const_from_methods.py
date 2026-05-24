#!/usr/bin/env python3
"""
Remove const from lines with method invocations - simple and reliable
"""

import os
import re
from pathlib import Path

def remove_const_from_methods(project_root):
    """Remove const from lines that have method calls"""
    lib_path = Path(project_root) / "lib"
    fixed_files = []
    
    for root, dirs, files in os.walk(lib_path):
        for file in files:
            if file.endswith(".dart"):
                file_path = Path(root) / file
                try:
                    with open(file_path, 'r', encoding='utf-8') as f:
                        lines = f.readlines()
                    
                    modified = False
                    for i, line in enumerate(lines):
                        # Check if line has const and a method call
                        if 'const ' in line and ('DesktopOptimizedWidgets.' in line or 'DesktopAppWrapper.' in line):
                            # Remove const keyword
                            new_line = line.replace('const ', '', 1)
                            if new_line != line:
                                lines[i] = new_line
                                modified = True
                    
                    if modified:
                        with open(file_path, 'w', encoding='utf-8') as f:
                            f.writelines(lines)
                        fixed_files.append(str(file_path.relative_to(project_root)))
                        print(f"✅ Fixed: {file_path.relative_to(project_root)}")
                
                except Exception as e:
                    print(f"❌ Error in {file_path}: {e}")
    
    return fixed_files

if __name__ == "__main__":
    import sys
    project_root = sys.argv[1] if len(sys.argv) > 1 else os.getcwd()
    
    print("🔧 Removing const from method invocations...")
    print(f"📁 Project: {project_root}")
    print()
    
    fixed = remove_const_from_methods(project_root)
    
    print()
    print(f"✅ Fixed {len(fixed)} files")
    if fixed:
        print("\n📝 Fixed files:")
        for f in sorted(set(fixed)):
            print(f"  ✅ {f}")
    
    print("\n✨ Done! Run: flutter analyze")
