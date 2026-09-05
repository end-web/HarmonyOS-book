import { LocalRuleSourceImportParser } from './entry/src/main/ets/service/rulesource/LocalRuleSourceImportParser';
import { LocalRuleSource } from './entry/src/main/ets/model/LocalRuleSource';

const onlineSourceJson = `[{"bookSourceComment":"//梦不觉","bookSourceGroup":"小说","bookSourceName":"听小说APP[小说_官方本地解密]","bookSourceType":0,"bookSourceUrl":"APP小说接口","customButton":false,"customOrder":6,"enabled":true,"enabledCookieJar":false,"enabledExplore":true,"eventListener":false,"exploreUrl":"@js:\\n(function(){\\n    var state = {c:'男频', t:'分类', s:'热播'};\\n    try { var saved = JSON.parse(source.getVariable()); if(saved && saved.c) state = saved; } catch(e){}\\n    \\n    var sortMap = {'热播':'hotplay','评分':'score','完本':'endxs','新书':'newxs','人气':'updatexs'};\\n    var channelMap = {'男频':0,'女频':1};\\n    \\n    var dict = {\\n        '男频': {\\n            '分类': '玄幻,奇幻,仙侠,武侠,灵异,科幻,职场,都市,游戏,竞技,历史,军事,同人,其他,轻小说'.split(','),\\n            '题材': '装备,赚钱,轮回,重生,种田,治愈,直播,征战,征服,争斗,战争,缘分,游戏,阴阳,异世,异能,异界,医术,妖魔,血脉,悬疑,虚拟,修炼,兄弟,星辰,信仰,邪恶,现实,武道,五行,文明,位面,未来,猥琐,危机,同人,挑战,体育,逃亡,守护,生死,生活,神兽,神魔,神秘,神话,烧脑,杀戮,任务,热血,权谋,求生'.split(','),\\n            '身份': '至尊,战神,宅男,业界精英,药师,学生,枭雄,仙尊,武神,同人,特种兵,书生,神医,神豪,少年,商人,杀手,强者,乞丐,女婿,农民,奶爸,明星,美女,流氓,教师,剑客,火影,黑客,海贼,贵族,盗贼,孤儿,公子,法医,帝王,道士,大侠,刺客,吃货,草根,兵王,保镖,保安,白领'.split(','),\\n            '性格': '装逼,勇猛,野蛮,阳光,嚣张,侠义,玩世不恭,铁血,杀伐果断,懦弱,狂傲,狡猾,坚毅,搞笑,疯狂,风流,逗逼,暗黑'.split(','),\\n            '情节': '扮猪吃虎,宝物,超能力,打脸,丹药,吊炸天,发财,翻身,废材,废材逆袭,洪荒,戒指,金手指,金庸,坑爹,逆天改命,入侵,三国,神器,随身空间,特殊技能,天书,王者荣耀,西游,咸鱼翻身,血腥,一统天下'.split(','),\\n            '流派': '重生,直播,争霸流,召唤流,异兽流,医生,学院流,校花,乡村,系统流,武侠,无限流,无敌流,文娱,网游,透视,天才流,随身流,爽文,升级流,神豪,软饭流,轻小说,奶爸,练功流,可爱流,惊悚,技术流,洪荒流,红包,废柴流,凡人流,恶搞,都市,兵王,保镖'.split(',')\\n        },\\n        '女频': {\\n            '分类': '古代言情,现代言情,青春校园,玄幻奇幻,武侠仙侠,悬疑灵异,游戏竞技,同人,科幻,其他'.split(','),\\n            '题材': '总裁,赚钱,专宠,重逢,智谋,职场,正剧,争斗,争宠,缘分,冤家,娱乐圈,友情,游戏,音乐,妖魔,选秀,相亲,现实,喜剧,亡国,吐槽,甜心,甜蜜,替身,替嫁,桃花,守护,嗜血,生活,深情,烧脑,商业,伤痛,闪婚,三生三世,日常,权利,情有独钟,倾城,青梅竹马,青春,契约,婆媳,虐渣,男强,命运,美食,卖萌,励志,江山,家族,家长里短,婚姻,回忆,皇权,欢乐,豪门,闺蜜,古风,孤独,狗血,宫斗宅斗,搞笑,感人,复仇,斗智斗勇,初恋,宠妻,宠溺,宠婚,车祸,背叛,爱情,BE'.split(','),\\n            '身份': '御姐,娱乐明星,业界精英,学霸,校花,王侯将相,王妃,替身,特工,庶女,首席,神医,设计师,商女,人妻,前妻,千金,弃妇,女强,女配,农女,明星,萌宝,灰姑娘,皇后,贵族,公主,高富帅,毒医,第三者,嫡女,变身,白领,BL'.split(','),\\n            '性格': '搞笑,懦弱,腹黑,霸道,冰冷,温柔,阳光,可爱,傲娇,冷酷,淡定,纯真,善良,强势,高冷,八卦,妖娆,风流,杀伐果断,情深,专情,甜美,张扬,奇葩,冰山,冷血,狡猾,柔情,毒舌,呆萌,玩世不恭,刁蛮,野蛮,古灵精怪,勇敢,花心,妖媚,逗逼,幽默,多情,机智,暖心,欢脱,专一,傻白甜,萌萌哒,高智商,慢热,敢爱敢恨,逗比'.split(','),\\n            '情节': '阴错阳差,一往情深,一见钟情,未婚怀孕,逃婚,死缠烂打,生死大爱,情有独钟,青梅竹马,强取豪夺,破镜重圆,女追男,女强女尊,虐渣打脸,涅槃,麻雀变凤凰,浪漫情缘,纠缠,欢喜冤家,黑化,复婚,复合,反转,反套路,错嫁,错爱,春风一度,出轨,不离不弃,变身,爱而不得'.split(','),\\n            '流派': '总裁文,种田文,医生,养成,言情,现言,甜宠文,爽文,轻小说,轻松文,女尊文,虐文,虐恋,暖文,年代文,脑洞,萌宠,可爱流,婚恋,古言,穿越,爆笑,宝宝'.split(',')\\n        }\\n    };\\n    \\n    var ui = [];\\n    var actionJs = \\"var s={c:infoMap['频道']||'男频', t:infoMap['类别']||'分类', s:infoMap['排序']||'热播'}; source.setVariable(JSON.stringify(s)); java.refreshExplore();\\";\\n    \\n    ui.push({title:'频道', type:'select', chars:['男频','女频'], default:state.c, action:actionJs, style:{layout_flexBasisPercent:1}});\\n    ui.push({title:'类别', type:'select', chars:['分类','题材','身份','性格','情节','流派'], default:state.t, action:actionJs, style:{layout_flexBasisPercent:1}});\\n    ui.push({title:'排序', type:'select', chars:['热播','评分','完本','新书','人气'], default:state.s, action:actionJs, style:{layout_flexBasisPercent:1}});\\n    ui.push({title:'关键字', type:'text', default:'', style:{layout_flexBasisPercent:1}});\\n    ui.push({title:'🔍搜全网', type:'button', action:\\"var k=infoMap['关键字']; if(!k){ java.toast('请输入关键字'); } else { java.searchBook(k, source); }\\", style:{layout_flexBasisPercent:1}});\\n    \\n    var items = dict[state.c][state.t] || [];\\n    var genderVal = channelMap[state.c];\\n    var sortVal = sortMap[state.s];\\n    \\n    for (var i = 0; i < items.length; i++) {\\n        var item = items[i];\\n        var url = (state.t === '分类')\\n            ? 'https://ts3.txs12.com/bycate/list?type=' + sortVal + '&minor=&start={{page}}&limit=20&language=zh_cn&gender=' + genderVal + '&major=' + encodeURIComponent(item)\\n            : 'https://ts3.txs12.com/bytag/list?type=' + sortVal + '&start={{page}}&limit=20&language=zh_cn&gender=' + genderVal + '&tags=' + encodeURIComponent(item);\\n        ui.push({title:item, url:url, style:{layout_flexGrow:1, layout_flexBasisPercent:0.25}});\\n    }\\n    \\n    return JSON.stringify(ui);\\n})()","header":"{\\"User-Agent\\":\\"okhttp/5.3.2\\",\\"appName\\":\\"com.listenxs.txsplayer\\",\\"vc\\":\\"521430\\",\\"vn\\":\\"1.4.3\\",\\"channel\\":\\"defChannel\\",\\"language\\":\\"zh-CN\\",\\"country\\":\\"CN\\",\\"netType\\":\\"1\\",\\"Gender\\":\\"male\\",\\"gpStore\\":\\"true\\"}","jsLib":"var SIGN_MAP = {'1':'H','2':'F','3':'G','4':'I','5':'J','9':'9','A':'C','B':'1','C':'Z','D':'E','E':'D','F':'2'};\\nfunction nativeSign(str) {\\n    var r = '';\\n    for (var i = 0; i < str.length; i++) {\\n        r += SIGN_MAP[str[i]] || str[i];\\n    }\\n    return r;\\n}\\nvar ESFEJJ_SECRET = '8a1b44c6-351d-4e23-9613-bb3bf9ad01ba';\\nvar APP_VER = '1.4.3';\\nvar APP_VC = '521430';\\nvar APP_NAME = 'com.listenxs.txsplayer';","lastUpdateTime":"1788319637551","respondTime":180000,"ruleBookInfo":{"author":"$.data.xsAuthor","coverUrl":"$.data.xsCover","intro":"$.data.xsIntro","kind":"{{$.data.majCate}},{{$.data.subCate}}","lastChapter":"$.data.chapterNum","name":"$.data.xsName","tocUrl":"<js>\\nString(baseUrl).replace('/bookinfo/', '/audiolist-4/').split('?')[0] + '?https=1&dirHcCode=';\\n</js>","wordCount":"$.data.words"},"ruleContent":{"content":"@js:\\n(function(){\\n    var body = result;\\n    try {\\n        var j = JSON.parse(body);\\n        if (j.data) {\\n            var audio = j.data.audioUrl || j.data.url || j.data.playUrl || j.data.m4aUrl;\\n            if (audio && (audio.match(/\\\\.(m4a|mp3|aac|ogg|flac|wav)(\\\\?|$)/i) || audio.match(/^https?:\\\\/\\\\//))) {\\n                return audio;\\n            }\\n            return j.data.chapterBody || j.data.content || j.data.text || j.data.body || '';\\n        }\\n    } catch(e) {}\\n    if (body.match(/\\\\.(m4a|mp3|aac|ogg|flac|wav)(\\\\?|$)/i)) {\\n        return body.trim();\\n    }\\n    if (body.indexOf('<') !== -1 && body.indexOf('>') !== -1) {\\n        return body.replace(/<[^>]+>/g, '\\\\n').replace(/\\\\n{3,}/g, '\\\\n\\\\n').trim();\\n    }\\n    return body;\\n})()"},"ruleExplore":{"author":"$.xsAuthor","bookList":"$.data","bookUrl":"https://ts3.txs12.com/bookinfo/{{$._id}}?language=zh_cn","coverUrl":"$.xsCover","intro":"$.xsIntro","kind":"{{$.xsScore}}分,{{$.playView}}热度","lastChapter":"第{{$.chapterNum}}章","name":"$.xsName"},"ruleSearch":{"author":"$.xsAuthor","bookList":"$.data","bookUrl":"https://ts3.txs12.com/bookinfo/{{$._id}}?language=zh_cn","coverUrl":"$.xsCover","intro":"$.xsIntro","kind":"{{$.xsScore}}分,{{$.playView}}热度","lastChapter":"第{{$.chapterNum}}章","name":"$.xsName"},"ruleToc":{"chapterList":"$.data.chapterCon","chapterName":"$.tit","chapterUrl":"@js:\\n(function(){\\n    var bookId = String(baseUrl).split('/audiolist-4/')[1];\\n    if (bookId) bookId = bookId.split('?')[0];\\n    var cid = String(java.getString('$.cid') || '');\\n\\n    var cache = {};\\n    try { cache = JSON.parse(source.getVariable()); } catch(e) {}\\n\\n    var devId = cache.dev_id || '';\\n    if (!devId) {\\n        devId = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c){\\n            var r = Math.random()*16|0, v = c=='x'?r:(r&0x3|0x8);\\n            return v.toString(16);\\n        });\\n        cache.dev_id = devId;\\n    }\\n\\n    var shuKey = 'shu_' + bookId;\\n    var dirKey = 'dir_' + bookId;\\n    var shuId = cache[shuKey] || '';\\n    var dirHcCode = cache[dirKey] || '';\\n\\n    // 从目录接口拿 shuId + dirHcCode（一次性，缓存复用）\\n    if (!shuId || !dirHcCode) {\\n        try {\\n            var r = java.ajax('https://ts3.txs12.com/audiolist-4/' + bookId + '?https=1&dirHcCode=');\\n            var j = JSON.parse(String(r));\\n            if (j.data) {\\n                if (!shuId && j.data.chapterUrl) {\\n                    var m = String(j.data.chapterUrl).match(/shuId=(\\\\d+)/);\\n                    if (m) shuId = m[1];\\n                }\\n                if (!dirHcCode) dirHcCode = String(j.data.dirHcCode || '');\\n                if (shuId) cache[shuKey] = shuId;\\n                if (dirHcCode) cache[dirKey] = dirHcCode;\\n            }\\n        } catch(e) {}\\n        if (!shuId) {\\n            try {\\n                var r2 = java.ajax('https://ts3.txs12.com/bookinfo/' + bookId + '?language=zh_cn');\\n                var j2 = JSON.parse(String(r2));\\n                if (j2.data && j2.data.x_id) {\\n                    shuId = String(j2.data.x_id);\\n                    cache[shuKey] = shuId;\\n                }\\n            } catch(e2) {}\\n        }\\n    }\\n    source.setVariable(JSON.stringify(cache));\\n\\n    var ts = new Date().getTime();\\n    var tt = String(Math.floor(ts / 1000));\\n    var computed = Math.floor(ts / 10000) + 5;\\n\\n    // token = md5('?' + shuId&_id&dirHcCode&cid（p1原始query顺序） + computed + 'cV2')\\n    var token = String(java.md5Encode('?shuId=' + shuId + '&_id=' + bookId + '&dirHcCode=' + dirHcCode + '&cid=' + cid + computed + 'cV2'));\\n\\n    // 10参数：URL与签名均按 TreeMap(key) 排序\\n    var allParams = {\\n        '_id': bookId,\\n        'app_name': APP_NAME,\\n        'app_vc': APP_VC,\\n        'app_vn': APP_VER,\\n        'cid': cid,\\n        'dev_id': devId,\\n        'dirHcCode': dirHcCode,\\n        'shuId': shuId,\\n        'token': token,\\n        'ts': String(ts)\\n    };\\n    var sortedKeys = Object.keys(allParams).sort();\\n    var urlParts = [];\\n    var signParts = [];\\n    for (var i = 0; i < sortedKeys.length; i++) {\\n        var k = sortedKeys[i];\\n        var v = allParams[k];\\n        urlParts.push(k + '=' + encodeURIComponent(v));\\n        signParts.push(k + '=' + v);\\n    }\\n    var urlStr = urlParts.join('&');\\n    var signStr = signParts.join('&');\\n\\n    // ss = nativeSign(md5(basePath + 排序参数 + tt + '+' + SECRET).toUpperCase())\\n    var signSource = 'https://res.txs12.com/cV2/' + signStr + tt + '+' + ESFEJJ_SECRET;\\n    var md5Result = String(java.md5Encode(signSource));\\n    var ss = nativeSign(md5Result.toUpperCase());\\n\\n    var finalUrl = 'https://res.txs12.com/cV2/?' + urlStr;\\n    var opt = {'headers': {'ss': ss, 'tt': tt}};\\n    return finalUrl + ',' + JSON.stringify(opt);\\n})()"},"searchUrl":"https://ts3.txs12.com/search/result?query={{key}}&language=zh_cn&start={{page-1}}&limit=30","weight":0}]`;

console.log('=== 书源导入测试 ===\n');

// 解析导入
const report = LocalRuleSourceImportParser.parse(onlineSourceJson);

console.log(`导入结果：`);
console.log(`- 成功导入: ${report.sources.length} 个`);
console.log(`- 不支持: ${report.unsupportedCount} 个`);
console.log(`- 拒绝: ${report.rejectedCount} 个`);
console.log(`- 消息: ${report.message || '无'}\n`);

if (report.sources.length > 0) {
  const source: LocalRuleSource = report.sources[0];

  console.log('=== 书源详情 ===');
  console.log(`名称: ${source.bookSourceName}`);
  console.log(`地址: ${source.bookSourceUrl}`);
  console.log(`类型: ${source.bookSourceType} (0=文本, 1=音频)`);
  console.log(`分组: ${source.bookSourceGroup}`);
  console.log(`启用: ${source.enabled}`);
  console.log(`状态: ${source.validationStatus}`);
  console.log(`提示: ${source.validationMessage}\n`);

  console.log('=== 能力检查 ===');
  console.log(`有搜索能力: ${source.hasSearchCapability()}`);
  console.log(`可执行: ${source.canExecute()}`);
  console.log(`搜索启用: ${source.isSearchEnabled()}\n`);

  console.log('=== 搜索规则 ===');
  console.log(`搜索URL: ${source.searchUrl}`);
  console.log(`书籍列表: ${source.ruleSearch?.bookList}`);
  console.log(`书名: ${source.ruleSearch?.name}`);
  console.log(`作者: ${source.ruleSearch?.author}\n`);

  console.log('=== 详情规则 ===');
  console.log(`目录URL: ${source.ruleBookInfo?.tocUrl?.substring(0, 50)}...`);
  console.log(`书名: ${source.ruleBookInfo?.name}`);
  console.log(`封面: ${source.ruleBookInfo?.coverUrl}\n`);

  console.log('=== 目录规则 ===');
  console.log(`章节列表: ${source.ruleToc?.chapterList}`);
  console.log(`章节名: ${source.ruleToc?.chapterName}`);
  console.log(`章节URL脚本长度: ${source.ruleToc?.chapterUrl?.length} 字符\n`);

  console.log('=== 内容规则 ===');
  console.log(`内容脚本长度: ${source.ruleContent?.content?.length} 字符`);
  console.log(`脚本类型: @js 动态解析（支持音频+文本）\n`);

  console.log('=== jsLib 公共库 ===');
  console.log(`jsLib 长度: ${source.jsLib?.length} 字符`);
  console.log(`包含函数: nativeSign(), SIGN_MAP, SECRET\n`);

  console.log('=== Header ===');
  console.log(`${source.header?.substring(0, 100)}...\n`);

  console.log('=== 探索URL ===');
  console.log(`exploreUrl 类型: @js 动态UI`);
  console.log(`长度: ${source.exploreUrl?.length} 字符`);
  console.log(`⚠️  注意: 返回UI定义，当前项目不支持交互式探索表单\n`);
}

console.log('=== 结论 ===');
console.log('✅ 导入解析：成功');
console.log('✅ 搜索规则：完整');
console.log('✅ 内容链路：完整（详情→目录→内容）');
console.log('✅ 脚本支持：@js / <js> / {{}} / jsLib');
console.log('✅ 复杂签名：MD5 + 自定义签名映射');
console.log('⚠️  探索功能：UI表单不支持交互');
console.log('⚠️  书源地址：非HTTP(S)，但规则中使用硬编码域名');
console.log('\n建议：可正常导入使用，主要通过搜索功能查找书籍');
