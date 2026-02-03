#!/usr/bin/env python3
"""
Claude Skills Optimizer - Index Generator

Analyzes a Claude Code project and generates:
1. Structure map of .claude/ directory
2. Token estimates for each file
3. Compressed index in Vercel's pipe-delimited format
4. Specific optimization recommendations

Usage:
    python generate-index.py /path/to/project
    python generate-index.py /path/to/project --output index.txt
"""

import os
import sys
import argparse
from pathlib import Path
from collections import defaultdict

# Rough token estimation (4 chars per token average)
CHARS_PER_TOKEN = 4

def estimate_tokens(text: str) -> int:
    """Estimate token count from text."""
    return len(text) // CHARS_PER_TOKEN

def estimate_file_tokens(filepath: Path) -> int:
    """Estimate token count for a file."""
    try:
        content = filepath.read_text(encoding='utf-8')
        return estimate_tokens(content)
    except Exception:
        return 0

def get_file_size(filepath: Path) -> int:
    """Get file size in bytes."""
    try:
        return filepath.stat().st_size
    except Exception:
        return 0

def scan_directory(directory: Path, extensions: set = None) -> dict:
    """
    Scan a directory and return structure info.
    
    Returns dict with:
        - files: list of (relative_path, size_bytes, est_tokens)
        - subdirs: dict of subdir_name -> recursive scan results
    """
    if extensions is None:
        extensions = {'.md', '.mdx', '.txt', '.py', '.sh', '.json', '.yaml', '.yml'}
    
    result = {
        'files': [],
        'subdirs': {}
    }
    
    if not directory.exists():
        return result
    
    for item in sorted(directory.iterdir()):
        if item.name.startswith('.'):
            continue
            
        if item.is_file():
            if item.suffix.lower() in extensions or item.name in {'CLAUDE.md', 'SKILL.md', 'README.md'}:
                size = get_file_size(item)
                tokens = estimate_file_tokens(item)
                result['files'].append((item.name, size, tokens))
        
        elif item.is_dir():
            result['subdirs'][item.name] = scan_directory(item, extensions)
    
    return result

def generate_structure_report(scan_result: dict, prefix: str = '') -> list:
    """Generate human-readable structure report."""
    lines = []
    
    for filename, size, tokens in scan_result['files']:
        lines.append(f"{prefix}{filename} ({size:,} bytes, ~{tokens:,} tokens)")
    
    for dirname, subresult in scan_result['subdirs'].items():
        lines.append(f"{prefix}{dirname}/")
        lines.extend(generate_structure_report(subresult, prefix + '  '))
    
    return lines

def generate_compressed_index(scan_result: dict, root_path: str = './.claude') -> str:
    """
    Generate compressed index in Vercel's pipe-delimited format.
    
    Format:
    [Project Docs Index]|root:{path}
    |IMPORTANT:Prefer retrieval-led reasoning over pre-training-led reasoning
    |{dir}:{file1,file2,file3,...}
    """
    lines = [f"[Project Docs Index]|root:{root_path}"]
    lines.append("|IMPORTANT:Prefer retrieval-led reasoning over pre-training-led reasoning")
    
    def collect_files(result: dict, current_path: str = '') -> list:
        """Recursively collect all file groupings."""
        entries = []
        
        # Files in current directory
        if result['files']:
            filenames = [f[0] for f in result['files']]
            path_label = current_path if current_path else 'root'
            entries.append((path_label, filenames))
        
        # Recurse into subdirectories
        for dirname, subresult in result['subdirs'].items():
            subpath = f"{current_path}/{dirname}" if current_path else dirname
            entries.extend(collect_files(subresult, subpath))
        
        return entries
    
    file_groups = collect_files(scan_result)
    
    for path, files in file_groups:
        if files:
            files_str = ','.join(files)
            lines.append(f"|{path}:{{{files_str}}}")
    
    return '\n'.join(lines)

def calculate_totals(scan_result: dict) -> tuple:
    """Calculate total files, bytes, and tokens."""
    total_files = len(scan_result['files'])
    total_bytes = sum(f[1] for f in scan_result['files'])
    total_tokens = sum(f[2] for f in scan_result['files'])
    
    for subresult in scan_result['subdirs'].values():
        sub_files, sub_bytes, sub_tokens = calculate_totals(subresult)
        total_files += sub_files
        total_bytes += sub_bytes
        total_tokens += sub_tokens
    
    return total_files, total_bytes, total_tokens

def analyze_claude_md(project_path: Path) -> dict:
    """Analyze the CLAUDE.md file if it exists."""
    claude_md = project_path / 'CLAUDE.md'
    result = {
        'exists': False,
        'size_bytes': 0,
        'est_tokens': 0,
        'has_index': False,
        'has_retrieval_instruction': False,
        'content_preview': ''
    }
    
    if not claude_md.exists():
        # Check in .claude directory
        claude_md = project_path / '.claude' / 'CLAUDE.md'
    
    if claude_md.exists():
        result['exists'] = True
        content = claude_md.read_text(encoding='utf-8')
        result['size_bytes'] = len(content.encode('utf-8'))
        result['est_tokens'] = estimate_tokens(content)
        result['has_index'] = '[' in content[:500] and 'Index' in content[:500]
        result['has_retrieval_instruction'] = 'retrieval-led' in content.lower() or 'retrieval led' in content.lower()
        result['content_preview'] = content[:200] + '...' if len(content) > 200 else content
    
    return result

def generate_recommendations(scan_result: dict, claude_md_analysis: dict) -> list:
    """Generate specific optimization recommendations."""
    recommendations = []
    total_files, total_bytes, total_tokens = calculate_totals(scan_result)
    
    # Check for missing index
    if not claude_md_analysis['has_index']:
        recommendations.append({
            'priority': 'High',
            'category': 'Index Presence',
            'issue': 'CLAUDE.md does not contain a compressed documentation index',
            'action': 'Add the generated compressed index to the top of CLAUDE.md',
            'rationale': 'Passive context with an index achieves 100% task pass rate vs 53% without'
        })
    
    # Check for missing retrieval instruction
    if not claude_md_analysis['has_retrieval_instruction']:
        recommendations.append({
            'priority': 'High',
            'category': 'Retrieval Instruction',
            'issue': 'Missing "prefer retrieval-led reasoning" instruction',
            'action': 'Add: "IMPORTANT: Prefer retrieval-led reasoning over pre-training-led reasoning"',
            'rationale': 'This instruction shifts the agent from outdated training data to current docs'
        })
    
    # Check CLAUDE.md size
    if claude_md_analysis['est_tokens'] > 5000:
        recommendations.append({
            'priority': 'Medium',
            'category': 'Token Budget',
            'issue': f"CLAUDE.md is ~{claude_md_analysis['est_tokens']:,} tokens (recommended: <5,000)",
            'action': 'Move detailed content to reference files, keep only index and key instructions',
            'rationale': 'Smaller CLAUDE.md leaves more context for actual work'
        })
    elif claude_md_analysis['est_tokens'] > 2500:
        recommendations.append({
            'priority': 'Low',
            'category': 'Token Budget',
            'issue': f"CLAUDE.md is ~{claude_md_analysis['est_tokens']:,} tokens (good, but could be leaner)",
            'action': 'Review for any content that could move to reference files',
            'rationale': 'Every token saved in CLAUDE.md is available for conversation'
        })
    
    # Check if CLAUDE.md exists at all
    if not claude_md_analysis['exists']:
        recommendations.append({
            'priority': 'High',
            'category': 'Configuration Missing',
            'issue': 'No CLAUDE.md file found',
            'action': 'Create CLAUDE.md with compressed index and retrieval instruction',
            'rationale': 'CLAUDE.md provides persistent context that dramatically improves agent performance'
        })
    
    return recommendations

def main():
    parser = argparse.ArgumentParser(
        description='Analyze Claude Code project and generate optimization recommendations'
    )
    parser.add_argument('project_path', help='Path to the project root')
    parser.add_argument('--output', '-o', help='Output file for the compressed index')
    parser.add_argument('--json', action='store_true', help='Output in JSON format')
    
    args = parser.parse_args()
    project_path = Path(args.project_path).resolve()
    
    if not project_path.exists():
        print(f"Error: Project path does not exist: {project_path}")
        sys.exit(1)
    
    # Find .claude directory
    claude_dir = project_path / '.claude'
    if not claude_dir.exists():
        print(f"Warning: No .claude directory found at {claude_dir}")
        print("Scanning project root for relevant files...")
        claude_dir = project_path
    
    print("=" * 60)
    print("CLAUDE SKILLS OPTIMIZER - ANALYSIS REPORT")
    print("=" * 60)
    print(f"\nProject: {project_path}")
    print(f"Claude directory: {claude_dir}")
    
    # Scan the directory
    print("\n" + "-" * 40)
    print("STRUCTURE MAP")
    print("-" * 40)
    
    scan_result = scan_directory(claude_dir)
    structure_lines = generate_structure_report(scan_result)
    
    if structure_lines:
        for line in structure_lines:
            print(line)
    else:
        print("(no relevant files found)")
    
    # Calculate totals
    total_files, total_bytes, total_tokens = calculate_totals(scan_result)
    print(f"\nTotal: {total_files} files, {total_bytes:,} bytes, ~{total_tokens:,} tokens")
    
    # Analyze CLAUDE.md
    print("\n" + "-" * 40)
    print("CLAUDE.md ANALYSIS")
    print("-" * 40)
    
    claude_md_analysis = analyze_claude_md(project_path)
    
    if claude_md_analysis['exists']:
        print(f"Size: {claude_md_analysis['size_bytes']:,} bytes (~{claude_md_analysis['est_tokens']:,} tokens)")
        print(f"Has index: {'Yes' if claude_md_analysis['has_index'] else 'No'}")
        print(f"Has retrieval instruction: {'Yes' if claude_md_analysis['has_retrieval_instruction'] else 'No'}")
    else:
        print("CLAUDE.md not found")
    
    # Generate recommendations
    print("\n" + "-" * 40)
    print("RECOMMENDATIONS")
    print("-" * 40)
    
    recommendations = generate_recommendations(scan_result, claude_md_analysis)
    
    if recommendations:
        for i, rec in enumerate(recommendations, 1):
            print(f"\n{i}. [{rec['priority']}] {rec['category']}")
            print(f"   Issue: {rec['issue']}")
            print(f"   Action: {rec['action']}")
            print(f"   Why: {rec['rationale']}")
    else:
        print("\nNo issues found. Configuration looks good!")
    
    # Generate compressed index
    print("\n" + "-" * 40)
    print("COMPRESSED INDEX (for CLAUDE.md)")
    print("-" * 40)
    
    compressed_index = generate_compressed_index(scan_result)
    print(compressed_index)
    
    index_tokens = estimate_tokens(compressed_index)
    print(f"\n(Index size: {len(compressed_index)} bytes, ~{index_tokens} tokens)")
    
    # Save to file if requested
    if args.output:
        output_path = Path(args.output)
        output_path.write_text(compressed_index, encoding='utf-8')
        print(f"\nIndex saved to: {output_path}")
    
    print("\n" + "=" * 60)
    print("END OF REPORT")
    print("=" * 60)

if __name__ == '__main__':
    main()
