#!/usr/bin/env python3
"""
Desktop Optimization Converter Script
Automatically converts all Flutter pages to use desktop-optimized widgets
"""

import os
import re
import sys
from pathlib import Path

class DesktopConverter:
    def __init__(self, project_root):
        self.project_root = Path(project_root)
        self.lib_path = self.project_root / "lib"
        self.converted_files = []
        self.skipped_files = []
        
    def find_page_files(self):
        """Find all *_page.dart files"""
        page_files = []
        for root, dirs, files in os.walk(self.lib_path):
            for file in files:
                if file.endswith("_page.dart"):
                    page_files.append(Path(root) / file)
        return sorted(page_files)
    
    def add_imports(self, content):
        """Add necessary imports if not already present"""
        imports_to_add = [
            "import 'package:cultioo_business/shared/widgets/desktop_app_wrapper.dart';",
            "import 'package:cultioo_business/shared/widgets/desktop_optimized_widgets.dart';",
        ]
        
        for imp in imports_to_add:
            if imp not in content:
                # Find the last import statement
                last_import_match = None
                for match in re.finditer(r"^import .*?;$", content, re.MULTILINE):
                    last_import_match = match
                
                if last_import_match:
                    insert_pos = last_import_match.end()
                    content = content[:insert_pos] + f"\n{imp}" + content[insert_pos:]
                else:
                    # No imports found, add at the beginning after any comments
                    content = imp + "\n" + content
        
        return content
    
    def replace_hardcoded_sizes(self, content):
        """Replace hardcoded sizes with adaptive values"""
        replacements = [
            # Padding replacements
            (r"padding:\s*const\s+EdgeInsets\.all\(16\)", 
             "padding: DesktopAppWrapper.getPagePadding()"),
            (r"padding:\s*const\s+EdgeInsets\.all\(20\)", 
             "padding: DesktopAppWrapper.getPagePadding()"),
            (r"padding:\s*const\s+EdgeInsets\.symmetric\(\s*horizontal:\s*20\s*\)", 
             "padding: EdgeInsets.symmetric(horizontal: DesktopAppWrapper.getHorizontalPadding())"),
            (r"padding:\s*const\s+EdgeInsets\.symmetric\(\s*horizontal:\s*16\s*\)", 
             "padding: EdgeInsets.symmetric(horizontal: DesktopAppWrapper.getHorizontalPadding())"),
            
            # Spacing replacements
            (r"SizedBox\(\s*height:\s*12\s*\)", 
             "SizedBox(height: DesktopOptimizedWidgets.getSpacing())"),
            (r"SizedBox\(\s*height:\s*16\s*\)", 
             "SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2)"),
            (r"SizedBox\(\s*height:\s*24\s*\)", 
             "SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3)"),
            (r"SizedBox\(\s*height:\s*8\s*\)", 
             "SizedBox(height: DesktopOptimizedWidgets.getSpacing())"),
            
            # Font size replacements
            (r"fontSize:\s*16\s*[,\)]", 
             "fontSize: DesktopOptimizedWidgets.getFontSize(),"),
            (r"fontSize:\s*14\s*[,\)]", 
             "fontSize: DesktopOptimizedWidgets.getFontSize(),"),
            (r"fontSize:\s*18\s*[,\)]", 
             "fontSize: DesktopOptimizedWidgets.getFontSize() + 4,"),
            (r"fontSize:\s*20\s*[,\)]", 
             "fontSize: DesktopOptimizedWidgets.getFontSize() + 6,"),
            (r"fontSize:\s*24\s*[,\)]", 
             "fontSize: DesktopOptimizedWidgets.getFontSize() + 10,"),
            
            # Border radius replacements
            (r"BorderRadius\.circular\(16\)", 
             "BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius())"),
            (r"BorderRadius\.circular\(20\)", 
             "BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)"),
            (r"BorderRadius\.circular\(12\)", 
             "BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius())"),
        ]
        
        for pattern, replacement in replacements:
            content = re.sub(pattern, replacement, content)
        
        return content
    
    def replace_scaffold(self, content):
        """Replace Scaffold with DesktopAppWrapper.buildScaffold"""
        # Only replace if not already using DesktopAppWrapper
        if "DesktopAppWrapper.buildScaffold" not in content:
            # Find Scaffold( and replace with DesktopAppWrapper.buildScaffold(
            # This is a simple replacement - more complex cases might need manual review
            content = re.sub(
                r"return\s+Scaffold\(",
                "return DesktopAppWrapper.buildScaffold(\n      context: context,",
                content
            )
        
        return content
    
    def replace_appbar(self, content):
        """Replace AppBar with DesktopAppWrapper.buildAppBar"""
        if "DesktopAppWrapper.buildAppBar" not in content:
            # Find AppBar( title: Text(...) and replace
            content = re.sub(
                r"appBar:\s*AppBar\(\s*title:\s*Text\('([^']+)'\)",
                r"appBar: DesktopAppWrapper.buildAppBar(\n        context: context,\n        title: '\1'",
                content
            )
            content = re.sub(
                r'appBar:\s*AppBar\(\s*title:\s*Text\("([^"]+)"\)',
                r'appBar: DesktopAppWrapper.buildAppBar(\n        context: context,\n        title: "\1"',
                content
            )
        
        return content
    
    def convert_file(self, file_path):
        """Convert a single file"""
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()
            
            original_content = content
            
            # Apply conversions
            content = self.add_imports(content)
            content = self.replace_hardcoded_sizes(content)
            # Note: Scaffold and AppBar replacements are complex and might need manual review
            # content = self.replace_scaffold(content)
            # content = self.replace_appbar(content)
            
            # Only write if changes were made
            if content != original_content:
                with open(file_path, 'w', encoding='utf-8') as f:
                    f.write(content)
                self.converted_files.append(str(file_path))
                return True
            else:
                self.skipped_files.append(str(file_path))
                return False
        
        except Exception as e:
            print(f"❌ Error converting {file_path}: {e}")
            return False
    
    def run(self):
        """Run the conversion"""
        print("🚀 Starting Desktop Optimization Conversion...")
        print(f"📁 Project root: {self.project_root}")
        print()
        
        page_files = self.find_page_files()
        print(f"📄 Found {len(page_files)} page files to convert:")
        print()
        
        for i, file_path in enumerate(page_files, 1):
            relative_path = file_path.relative_to(self.project_root)
            print(f"  {i}. {relative_path}")
        
        print()
        print("=" * 80)
        print()
        
        # Convert each file
        for file_path in page_files:
            relative_path = file_path.relative_to(self.project_root)
            print(f"Converting: {relative_path}...", end=" ")
            
            if self.convert_file(file_path):
                print("✅ Done")
            else:
                print("⏭️  Skipped")
        
        print()
        print("=" * 80)
        print()
        print(f"✅ Converted: {len(self.converted_files)} files")
        print(f"⏭️  Skipped: {len(self.skipped_files)} files")
        print()
        
        if self.converted_files:
            print("📝 Converted files:")
            for file in self.converted_files:
                print(f"  ✅ {file}")
        
        print()
        print("⚠️  IMPORTANT NOTES:")
        print("  1. This script converted hardcoded sizes to adaptive values")
        print("  2. Scaffold and AppBar replacements were skipped (too complex)")
        print("  3. Please manually review the following:")
        print("     - Replace 'Scaffold(' with 'DesktopAppWrapper.buildScaffold('")
        print("     - Replace 'AppBar(' with 'DesktopAppWrapper.buildAppBar('")
        print("     - Add 'context: context,' parameter to new methods")
        print("  4. Test all pages on Desktop (macOS, Windows, Linux)")
        print("  5. Test all pages on Mobile (iOS, Android)")
        print()
        print("✨ Conversion complete! Run: git add -A && git commit -m 'Auto-convert pages to desktop-optimized'")

def main():
    if len(sys.argv) > 1:
        project_root = sys.argv[1]
    else:
        # Use current directory
        project_root = os.getcwd()
    
    converter = DesktopConverter(project_root)
    converter.run()

if __name__ == "__main__":
    main()
