#!/usr/bin/env python3
"""
fsearch.py - ファイル内容のAND検索スクリプト
使い方: python3 fsearch.py <dir> <keyword1> [keyword2] ...
キーワードが全て含まれるファイルの相対パスを標準出力に出力する
"""

import sys
import os

TEXT_EXTENSIONS = {
    '.md', '.txt', '.rst', '.csv', '.tsv',
    '.yaml', '.yml', '.toml', '.ini', '.conf',
    '.py', '.sh', '.js', '.html', '.css', '.json',
    '.tex', '.org', '.wiki',
}

def is_text_file(path):
    ext = os.path.splitext(path)[1].lower()
    return ext in TEXT_EXTENSIONS

def search_files(directory, keywords):
    keywords_lower = [kw.lower() for kw in keywords]
    matched = []

    for root, dirs, files in os.walk(directory):
        # 隠しフォルダをスキップ
        dirs[:] = sorted(d for d in dirs if not d.startswith('.'))

        for fname in sorted(files):
            if fname.startswith('.'):
                continue
            fpath = os.path.join(root, fname)
            if not is_text_file(fpath):
                continue

            try:
                with open(fpath, 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read().lower()
                # 全キーワードがファイル全体に含まれているか
                if all(kw in content for kw in keywords_lower):
                    rel = os.path.relpath(fpath, directory)
                    matched.append(rel)
            except (OSError, PermissionError):
                continue

    return matched

def main():
    if len(sys.argv) < 3:
        print("Usage: fsearch.py <dir> <keyword1> [keyword2] ...", file=sys.stderr)
        sys.exit(1)

    directory = sys.argv[1]
    keywords = sys.argv[2:]

    if not os.path.isdir(directory):
        print(f"Error: {directory} is not a directory", file=sys.stderr)
        sys.exit(1)

    results = search_files(directory, keywords)
    for r in results:
        print(r)

if __name__ == '__main__':
    main()
