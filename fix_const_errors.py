#!/usr/bin/env python3
"""
Fix const SizedBox errors - remove const from SizedBox with method calls
"""

import os
import re
from pathlib import Path

def fix_const_errors(project_root):
    """Fix all const SizedBox errors in the project"""
    lib_path = Path(project_root) / "lib"
    fixed_files = []
    
    for root, dirs, files in os.walk(lib_path):
        for file in files:
            if file.endswith(".dart"):
                file_path = Path(root) / file
                try:
                    with open(file_path, 'r', encoding='utf-8') as f:
                        content = f.read()
                    
                    original = content
                    
                    # Fix const SizedBox with method calls
                    # Pattern: const SizedBox(height: DesktopOptimizedWidgets.getSpacing()...)
                    content = re.sub(
                        r'const\s+SizedBox\(\s*height:\s*DesktopOptimizedWidgets\.',
                        'SizedBox(height: DesktopOptimizedWidgets.',
                        content
                    )
                    
                    # Fix const SizedBox with DesktopAppWrapper
                    content = re.sub(
                        r'const\s+SizedBox\(\s*height:\s*DesktopAppWrapper\.',
                        'SizedBox(height: DesktopAppWrapper.',
                        content
                    )
                    
                    # Fix const TextStyle with method calls
                    content = re.sub(
                        r'const\s+TextStyle\(\s*fontSize:\s*DesktopOptimizedWidgets\.',
                        'TextStyle(fontSize: DesktopOptimizedWidgets.',
                        content
                    )
                    
                    # Fix const BoxDecoration with method calls
                    content = re.sub(
                        r'const\s+BoxDecoration\(\s*borderRadius:\s*BorderRadius\.circular\(DesktopOptimizedWidgets\.',
                        'BoxDecoration(borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.',
                        content
                    )
                    
                    if content != original:
                        with open(file_path, 'w', encoding='utf-8') as f:
                            f.write(content)
                        fixed_files.append(str(file_path.relative_to(project_root)))
                        print(f"✅ Fixed: {file_path.relative_to(project_root)}")
                
                except Exception as e:
                    print(f"❌ Error in {file_path}: {e}")
    
    return fixed_files

if __name__ == "__main__":
    import sys
    project_root = sys.argv[1] if len(sys.argv) > 1 else os.getcwd()
    
    print("🔧 Fixing const expression errors...")
    print(f"📁 Project: {project_root}")
    print()
    
    fixed = fix_const_errors(project_root)
    
    print()
    print(f"✅ Fixed {len(fixed)} files")
    if fixed:
        print("\n📝 Fixed files:")
        for f in fixed:
            print(f"  ✅ {f}")
    
    print("\n✨ Done! Run: flutter run -d macos")
