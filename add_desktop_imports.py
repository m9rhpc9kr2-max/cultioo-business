#!/usr/bin/env python3
"""
Add desktop optimization imports to all pages (conservative approach)
Only adds imports, doesn't change any code
"""

import os
import re
from pathlib import Path

def add_desktop_imports(project_root):
    """Add desktop imports to all page files"""
    lib_path = Path(project_root) / "lib"
    fixed_files = []
    
    for root, dirs, files in os.walk(lib_path):
        for file in files:
            if file.endswith("_page.dart"):
                file_path = Path(root) / file
                try:
                    with open(file_path, 'r', encoding='utf-8') as f:
                        content = f.read()
                    
                    original = content
                    
                    # Check if imports are already there
                    has_desktop_wrapper = "import 'package:cultioo_business/shared/widgets/desktop_app_wrapper.dart';" in content
                    has_desktop_optimized = "import 'package:cultioo_business/shared/widgets/desktop_optimized_widgets.dart';" in content
                    
                    if not has_desktop_wrapper or not has_desktop_optimized:
                        # Find the last import statement
                        last_import_pos = 0
                        for match in re.finditer(r"^import .*?;$", content, re.MULTILINE):
                            last_import_pos = match.end()
                        
                        if last_import_pos > 0:
                            # Add imports after the last import
                            imports_to_add = []
                            if not has_desktop_wrapper:
                                imports_to_add.append("import 'package:cultioo_business/shared/widgets/desktop_app_wrapper.dart';")
                            if not has_desktop_optimized:
                                imports_to_add.append("import 'package:cultioo_business/shared/widgets/desktop_optimized_widgets.dart';")
                            
                            if imports_to_add:
                                new_imports = "\n".join(imports_to_add)
                                content = content[:last_import_pos] + "\n" + new_imports + content[last_import_pos:]
                    
                    if content != original:
                        with open(file_path, 'w', encoding='utf-8') as f:
                            f.write(content)
                        fixed_files.append(str(file_path.relative_to(project_root)))
                        print(f"✅ Added imports: {file_path.relative_to(project_root)}")
                
                except Exception as e:
                    print(f"❌ Error in {file_path}: {e}")
    
    return fixed_files

if __name__ == "__main__":
    import sys
    project_root = sys.argv[1] if len(sys.argv) > 1 else os.getcwd()
    
    print("📦 Adding desktop optimization imports...")
    print(f"📁 Project: {project_root}")
    print()
    
    fixed = add_desktop_imports(project_root)
    
    print()
    print(f"✅ Updated {len(fixed)} files")
    if fixed:
        print("\n📝 Updated files:")
        for f in sorted(set(fixed)):
            print(f"  ✅ {f}")
    
    print("\n✨ Done! Run: flutter analyze")
