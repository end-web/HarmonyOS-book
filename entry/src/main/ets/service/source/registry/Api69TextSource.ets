import type { SourceDefinition } from '../SourceDefinition';

const API69_SOURCE_JSON = `{
  "id": "api69_text",
  "name": "69书吧 APP API",
  "baseUrl": "https://app.novelapis.com/json",
  "desc": "文本源。基于 APP JSON API，搜索、详情、目录、正文均使用 POST。",
  "type": 0,
  "searchable": true,
  "headers": {
    "User-Agent": "NovelApp/2.1.8 (Android/16)",
    "Content-Type": "application/x-www-form-urlencoded",
    "Accept": "application/json, text/plain, */*"
  },
  "search": {
    "request": {
      "url": "https://app.novelapis.com/json/api_search.php",
      "method": "POST",
      "body": "searchkey={{key}}&page={{page}}&token={{token}}&timestamp={{timestamp}}&lang=jt",
      "responseType": "json"
    },
    "list": "$[*]",
    "item": {
      "name": "$.articlename",
      "author": "$.author",
      "cover": "$.img_url",
      "bookId": "$.articleid",
      "intro": "$.intro_des",
      "status": "$.isfull"
    }
  },
  "detail": {
    "request": {
      "url": "https://app.novelapis.com/json/api_info.php",
      "method": "POST",
      "body": "aid={{raw:bookId}}&token={{token}}&timestamp={{timestamp}}&lang=jt",
      "responseType": "json"
    },
    "fields": {
      "name": "$.articlename",
      "author": "$.author",
      "cover": "$.img_url",
      "intro": "$.intro_des || $.intro_p",
      "status": "$.sortname || $.isfull || $.keywords",
      "tocUrl": "$.articleid"
    }
  },
  "toc": {
    "request": {
      "url": "https://app.novelapis.com/json/api_indexlist.php",
      "method": "POST",
      "body": "aid={{raw:tocUrl}}&token={{token}}&timestamp={{timestamp}}&lang=jt",
      "responseType": "json"
    },
    "list": "$.list[*]",
    "item": {
      "name": "$.chaptername",
      "chapterId": "",
      "chapterUrl": "$.chapter_url"
    }
  },
  "content": {
    "request": {
      "url": "https://app.novelapis.com/json/api_read.php",
      "method": "POST",
      "body": "aid={{aid}}&cid={{cid}}&token={{token}}&timestamp={{timestamp}}&lang=jt",
      "responseType": "json"
    },
    "extract": "$.content || $.paragraphs[*]"
  },
  "category": {
    "menus": [
      {
        "title": "榜单",
        "tabs": [
          { "title": "最新入库", "url": "https://app.novelapis.com/json/api_class_list.php?page=1" },
          { "title": "字数榜", "url": "https://app.novelapis.com/json/api_class_list.php?order=words&page=1" }
        ]
      },
      {
        "title": "分类",
        "tabs": [
          { "title": "玄幻", "url": "https://app.novelapis.com/json/api_class_list.php?sortid=1&page=1" },
          { "title": "仙侠", "url": "https://app.novelapis.com/json/api_class_list.php?sortid=2&page=1" },
          { "title": "都市", "url": "https://app.novelapis.com/json/api_class_list.php?sortid=3&page=1" },
          { "title": "历史", "url": "https://app.novelapis.com/json/api_class_list.php?sortid=4&page=1" },
          { "title": "游戏", "url": "https://app.novelapis.com/json/api_class_list.php?sortid=5&page=1" },
          { "title": "科幻", "url": "https://app.novelapis.com/json/api_class_list.php?sortid=6&page=1" },
          { "title": "言情", "url": "https://app.novelapis.com/json/api_class_list.php?sortid=7&page=1" },
          { "title": "同人", "url": "https://app.novelapis.com/json/api_class_list.php?sortid=8&page=1" }
        ]
      },
      {
        "title": "标签",
        "tabs": [
          { "title": "克苏鲁", "url": "https://app.novelapis.com/json/api_tag.php?tag=%E5%85%8B%E8%8B%8F%E9%B2%81&page=1" },
          { "title": "穿越", "url": "https://app.novelapis.com/json/api_tag.php?tag=%E7%A9%BF%E8%B6%8A&page=1" },
          { "title": "系统", "url": "https://app.novelapis.com/json/api_tag.php?tag=%E7%B3%BB%E7%BB%9F&page=1" },
          { "title": "诸天", "url": "https://app.novelapis.com/json/api_tag.php?tag=%E8%AF%B8%E5%A4%A9&page=1" },
          { "title": "末世", "url": "https://app.novelapis.com/json/api_tag.php?tag=%E6%9C%AB%E4%B8%96&page=1" },
          { "title": "反派", "url": "https://app.novelapis.com/json/api_tag.php?tag=%E5%8F%8D%E6%B4%BE&page=1" }
        ]
      }
    ],
    "list": {
      "request": {
        "url": "{{raw:categoryEndpoint}}",
        "method": "POST",
        "body": "{{raw:categoryParams}}&token={{token}}&timestamp={{timestamp}}&lang=jt",
        "responseType": "json"
      },
      "list": "$[*]",
      "item": {
        "name": "$.articlename",
        "author": "$.author",
        "cover": "$.img_url",
        "bookId": "$.articleid",
        "intro": "$.intro_des",
        "status": "$.isfull"
      }
    }
  }
}`;

export const Api69TextSource: SourceDefinition = JSON.parse(API69_SOURCE_JSON) as SourceDefinition;
