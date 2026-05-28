#!/usr/bin/env bash
set -euo pipefail

# 默认参数
MAX_SOURCES=231
VALID_ONLY=false
OUTPUT_DIR="./book_sources_data"
PAGE_SIZE=20

# 解析参数
while [[ $# -gt 0 ]]; do
  case $1 in
    --max)
      MAX_SOURCES="$2"
      shift 2
      ;;
    --valid-only)
      VALID_ONLY=true
      shift
      ;;
    --output)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    *)
      echo "未知参数: $1"
      exit 1
      ;;
  esac
done

# 创建输出目录
mkdir -p "$OUTPUT_DIR"

echo "📡 开始获取 yiove 书源数据..."
echo "   最大数量: $MAX_SOURCES"
echo "   仅有效源: $VALID_ONLY"
echo "   输出目录: $OUTPUT_DIR"
echo ""

# 第一步：获取书源列表
echo "🔍 步骤 1/3: 获取书源列表..."
SEARCH_API="https://shuyuan-api.yiove.com/shuyuan/search"

# 计算需要的页数
TOTAL_PAGES=$(( (MAX_SOURCES + PAGE_SIZE - 1) / PAGE_SIZE ))

ALL_IDS=()
page=1

while [[ $page -le $TOTAL_PAGES ]]; do
  echo "   正在获取第 $page 页..."

  response=$(curl -s "${SEARCH_API}?search_key=%E5%90%AC%E4%B9%A6&search_type=book-sources&page=${page}&page_size=${PAGE_SIZE}")

  # 提取 ID 和有效性
  if [[ "$VALID_ONLY" == "true" ]]; then
    ids=$(echo "$response" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for item in data.get('items', []):
    if item.get('is_valid'):
        print(item['id'])
" 2>/dev/null || echo "")
  else
    ids=$(echo "$response" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for item in data.get('items', []):
    print(item['id'])
" 2>/dev/null || echo "")
  fi

  if [[ -z "$ids" ]]; then
    break
  fi

  while IFS= read -r id; do
    ALL_IDS+=("$id")
    if [[ ${#ALL_IDS[@]} -ge $MAX_SOURCES ]]; then
      break 2
    fi
  done <<< "$ids"

  ((page++))
done

TOTAL_COUNT=${#ALL_IDS[@]}
echo "✅ 找到 $TOTAL_COUNT 个书源"
echo ""

# 第二步：批量获取详情
echo "📥 步骤 2/3: 批量获取书源详情..."
DETAIL_API="https://shuyuan-api.yiove.com/shuyuan/book-source"

ALL_SOURCES="[]"
counter=0

for id in "${ALL_IDS[@]}"; do
  ((counter++))
  echo -ne "   进度: $counter/$TOTAL_COUNT\r"

  detail=$(curl -s "${DETAIL_API}/${id}" 2>/dev/null || echo "{}")

  if [[ "$detail" != "{}" ]]; then
    ALL_SOURCES=$(echo "$ALL_SOURCES" | python3 -c "
import json, sys
sources = json.load(sys.stdin)
detail = json.loads('''$detail''')
sources.append(detail)
print(json.dumps(sources, ensure_ascii=False))
" 2>/dev/null || echo "$ALL_SOURCES")
  fi

  # 避免请求过快
  sleep 0.1
done

echo ""
echo "✅ 获取完成"
echo ""

# 第三步：保存数据和生成报告
echo "💾 步骤 3/3: 保存数据..."

# 保存完整数据
echo "$ALL_SOURCES" > "$OUTPUT_DIR/book_sources_all.json"
echo "   已保存: $OUTPUT_DIR/book_sources_all.json"

# 保存仅有效书源
if [[ "$VALID_ONLY" == "false" ]]; then
  VALID_SOURCES=$(echo "$ALL_SOURCES" | python3 -c "
import json, sys
sources = json.load(sys.stdin)
valid = [s for s in sources if s.get('is_valid')]
print(json.dumps(valid, ensure_ascii=False, indent=2))
" 2>/dev/null || echo "[]")

  echo "$VALID_SOURCES" > "$OUTPUT_DIR/book_sources_valid.json"
  echo "   已保存: $OUTPUT_DIR/book_sources_valid.json"
fi

# 生成统计报告
python3 <<'PYEOF' > "$OUTPUT_DIR/book_sources_report.txt"
import json, sys
from collections import Counter

with open('$OUTPUT_DIR/book_sources_all.json', 'r', encoding='utf-8') as f:
    sources = json.load(f)

total = len(sources)
valid = sum(1 for s in sources if s.get('is_valid'))
invalid = total - valid

print("=" * 60)
print("📊 yiove 听书书源统计报告")
print("=" * 60)
print()
print(f"总书源数: {total}")
print(f"有效书源: {valid} ({valid*100//total if total > 0 else 0}%)")
print(f"失效书源: {invalid} ({invalid*100//total if total > 0 else 0}%)")
print()

# 分析规则类型
rule_types = Counter()
has_js = 0
has_json_path = 0
has_css = 0
has_xpath = 0
has_regex = 0

for source in sources:
    origin = source.get('origin_json', '')
    if not origin:
        continue

    try:
        rules = json.loads(origin)

        # 检查各种规则类型
        rule_str = json.dumps(rules)

        if '@js:' in rule_str or '<js>' in rule_str:
            has_js += 1
            rule_types['JavaScript'] += 1

        if '$.' in rule_str or '$..' in rule_str:
            has_json_path += 1
            rule_types['JSONPath'] += 1

        if any(k in rule_str for k in ['@text', '@href', '@src', '@attr']):
            has_css += 1
            rule_types['CSS选择器'] += 1

        if '//' in rule_str or 'xpath' in rule_str.lower():
            has_xpath += 1
            rule_types['XPath'] += 1

        if '##' in rule_str or 'regex' in rule_str.lower():
            has_regex += 1
            rule_types['正则表达式'] += 1

    except:
        pass

print("规则类型分布:")
print("-" * 60)
for rule_type, count in rule_types.most_common():
    print(f"  {rule_type:<20} {count:>4} 个书源")
print()

# Top 10 热门书源
print("🔥 Top 10 热门书源 (按浏览量):")
print("-" * 60)
top_sources = sorted(sources, key=lambda x: x.get('view_total', 0), reverse=True)[:10]
for i, s in enumerate(top_sources, 1):
    status = "✅" if s.get('is_valid') else "❌"
    print(f"  {i:2}. {status} {s.get('name', 'Unknown'):<25} {s.get('view_total', 0):>5} 次")
print()

print("=" * 60)
print(f"数据文件: {sys.argv[1]}")
print("=" * 60)

PYEOF

echo "   已保存: $OUTPUT_DIR/book_sources_report.txt"
echo ""

# 显示报告
cat "$OUTPUT_DIR/book_sources_report.txt"

echo ""
echo "✨ 完成！数据已保存到: $OUTPUT_DIR/"
