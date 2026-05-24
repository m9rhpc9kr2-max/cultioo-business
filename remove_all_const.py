#!/usr/bin/env python3
"""
Remove ALL const keywords from lines with Desktop method calls
"""

import os
from pathlib import Path

def remove_all_const(project_root):
    """Remove const from any line with Desktop method calls"""
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
                        # If line has Desktop method call, remove ALL const keywords
                        if 'DesktopOptimizedWidgets.' in line or 'DesktopAppWrapper.' in line:
                            # Remove all const keywords from this line
                            new_line = line.replace('const ', '')
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
    
    print("🔧 Removing ALL const from Desktop method calls...")
    print(f"📁 Project: {project_root}")
    print()
    
    fixed = remove_all_const(project_root)
    
    print()
    print(f"✅ Fixed {len(fixed)} files")
    
    print("\n✨ Done! Run: flutter analyze")
