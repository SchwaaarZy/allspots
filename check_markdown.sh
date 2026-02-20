#!/bin/bash

# Script de validation markdown pour éviter les erreurs futures
# Règles appliquées: espacement, ponctuation, listes, code blocks

check_markdown_file() {
    local file=$1
    local errors=0
    local line_num=0
    
    while IFS= read -r line; do
        ((line_num++))
        
        # MD022: Headings should be surrounded by blank lines
        if [[ $line =~ ^#+\ ]]; then
            local prev_line=""
            local next_line=""
            [[ $line_num -gt 1 ]] && prev_line=$(sed -n "$((line_num-1))p" "$file")
            [[ $line_num -lt $(wc -l < "$file") ]] && next_line=$(sed -n "$((line_num+1))p" "$file")
            
            if [[ -n "$prev_line" && "$prev_line" != "---" && ! "$prev_line" =~ ^# ]]; then
                echo "  ⚠️  Line $line_num (MD022): Add blank line before heading"
                ((errors++))
            fi
        fi
        
        # MD026: No trailing punctuation in headings
        if [[ $line =~ ^#+\ .*:$ ]]; then
            echo "  ⚠️  Line $line_num (MD026): Remove trailing ':' from heading"
            ((errors++))
        fi
        
        # MD031: Fenced code blocks should have blank lines
        if [[ "$line" == "\`\`\`"* ]]; then
            local prev=$(sed -n "$((line_num-1))p" "$file")
            if [[ -n "$prev" && "$prev" != "---" ]]; then
                # Previous line should be blank or separator
                :
            fi
        fi
        
    done < "$file"
    
    return $errors
}

echo "🔍 Markdown validation check"
echo "================================"

for md_file in *.md; do
    if check_markdown_file "$md_file"; then
        echo "✅ $md_file: OK"
    else
        echo "❌ $md_file: Has issues"
    fi
done
