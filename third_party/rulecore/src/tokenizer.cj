package rulecore

// A bounded, non-executing HTML lexer. This module never accesses the network,
// files, platform objects or evaluates source-supplied code.
let MAX_INPUT: Int64 = 16777216
let MAX_UTF16: Int64 = 4194304
let MAX_OUTPUT: Int64 = 33554432
let MAX_TOKENS: Int64 = 50000

func isSpace(c: UInt8): Bool {
    return c == 32 || c == 9 || c == 10 || c == 12 || c == 13
}

func isName(c: UInt8): Bool {
    return (c >= 65 && c <= 90) || (c >= 97 && c <= 122) ||
        (c >= 48 && c <= 57) || c == 45 || c == 58 || c == 95
}

func lower(c: UInt8): UInt8 {
    if (c >= 65 && c <= 90) { return c + 32 }
    return c
}

func matches(data: Array<UInt8>, offset: Int64, pattern: String): Bool {
    let expected = pattern.toArray()
    if (offset + expected.size > data.size) { return false }
    for (i in 0..expected.size) {
        if (lower(data[offset + i]) != expected[i]) { return false }
    }
    return true
}

func part(data: Array<UInt8>, start: Int64, end: Int64): String {
    return String.fromUtf8(data[start..end])
}

func namePart(data: Array<UInt8>, start: Int64, end: Int64): String {
    let bytes = Array<UInt8>(end - start, { i => lower(data[start + i]) })
    return String.fromUtf8(bytes)
}

func quoted(value: String): String {
    let result = StringBuilder()
    result.append("\"")
    let data = value.toArray()
    var start: Int64 = 0
    for (i in 0..data.size) {
        let c = data[i]
        if (c == 34 || c == 92 || c < 32) {
            if (i > start) { result.append(part(data, start, i)) }
            if (c == 34) { result.append("\\\"") }
            else if (c == 92) { result.append("\\\\") }
            else {
                let hex = "0123456789abcdef".toArray()
                result.append("\\u00")
                result.append(String.fromUtf8([hex[Int64(c / 16)], hex[Int64(c % 16)]]))
            }
            start = i + 1
        }
    }
    if (start < data.size) { result.append(part(data, start, data.size)) }
    result.append("\"")
    return result.toString()
}

class TokenWriter {
    let output = StringBuilder()
    let input: Array<UInt8>
    var count: Int64 = 0
    var bytes: Int64 = 0
    var bytePosition: Int64 = 0
    var utf16Position: Int64 = 0

    init(input: Array<UInt8>) {
        this.input = input
        output.append("{\"tokens\":[")
    }

    func offset(position: Int64): Int64 {
        while (bytePosition < position) {
            let value = input[bytePosition]
            if (value < 128 || value >= 192) { utf16Position += if (value >= 240) { 2 } else { 1 } }
            bytePosition++
        }
        return utf16Position
    }

    func range(start: Int64, end: Int64): String {
        let first = offset(start)
        let last = offset(end)
        return ",\"start\":" + first.toString() + ",\"end\":" + last.toString()
    }

    func add(token: String): Unit {
        count++
        bytes += token.size + 1
        if (count > MAX_TOKENS || bytes > MAX_OUTPUT - 64) {
            throw Exception("HTML token/output limit exceeded")
        }
        if (count > 1) { output.append(",") }
        output.append(token)
    }

    func text(start: Int64, end: Int64): Unit {
        if (end > start) {
            add("{\"type\":\"text\",\"text\":" + quoted(part(input, start, end)) + range(start, end) + "}")
        }
    }

    func finish(): String {
        output.append("],\"error\":\"\"}")
        return output.toString()
    }
}

public func tokenizeHtml(html: String): String {
    let data = html.toArray()
    if (data.size > MAX_INPUT) { throw Exception("HTML input limit exceeded") }
    var characters: Int64 = 0
    for (value in data) {
        if (value < 128 || value >= 192) { characters += if (value >= 240) { 2 } else { 1 } }
        if (characters > MAX_UTF16) { throw Exception("HTML character limit exceeded") }
    }
    let writer = TokenWriter(data)
    var pos: Int64 = 0
    var textStart: Int64 = 0
    var rawTag = ""
    while (pos < data.size) {
        if (!rawTag.isEmpty()) {
            let start = pos
            let closing = "</" + rawTag
            while (pos < data.size) {
                if (matches(data, pos, closing)) {
                    let after = pos + closing.size
                    if (after == data.size || isSpace(data[after]) || data[after] == 62 || data[after] == 47) { break }
                }
                pos++
            }
            writer.text(start, pos)
            rawTag = ""
            textStart = pos
            if (pos == data.size) { break }
        }
        if (data[pos] != 60) { pos++; continue }
        if (matches(data, pos, "<!--")) {
            writer.text(textStart, pos)
            pos += 4
            while (pos < data.size && !matches(data, pos, "-->")) { pos++ }
            if (pos < data.size) { pos += 3 }
            textStart = pos
            continue
        }
        if (pos + 1 < data.size && (data[pos + 1] == 33 || data[pos + 1] == 63)) {
            writer.text(textStart, pos)
            while (pos < data.size && data[pos] != 62) { pos++ }
            if (pos < data.size) { pos++ }
            textStart = pos
            continue
        }
        let tagStart = pos
        var cursor = pos + 1
        var isClose = false
        if (cursor < data.size && data[cursor] == 47) { isClose = true; cursor++ }
        if (cursor >= data.size || !((data[cursor] >= 65 && data[cursor] <= 90) ||
            (data[cursor] >= 97 && data[cursor] <= 122))) { pos++; continue }
        writer.text(textStart, tagStart)
        let nameStart = cursor
        while (cursor < data.size && isName(data[cursor])) { cursor++ }
        let name = namePart(data, nameStart, cursor)
        let attributes = StringBuilder()
        var attrCount: Int64 = 0
        var selfClosing = false
        while (cursor < data.size && data[cursor] != 62) {
            if (isSpace(data[cursor])) { cursor++; continue }
            if (data[cursor] == 47 && cursor + 1 < data.size && data[cursor + 1] == 62) {
                selfClosing = true; cursor++; break
            }
            let attrStart = cursor
            while (cursor < data.size && !isSpace(data[cursor]) && data[cursor] != 61 &&
                data[cursor] != 62 && data[cursor] != 47) { cursor++ }
            if (cursor == attrStart) { cursor++; continue }
            let attrName = namePart(data, attrStart, cursor)
            while (cursor < data.size && isSpace(data[cursor])) { cursor++ }
            var value = ""
            if (cursor < data.size && data[cursor] == 61) {
                cursor++
                while (cursor < data.size && isSpace(data[cursor])) { cursor++ }
                if (cursor < data.size && (data[cursor] == 34 || data[cursor] == 39)) {
                    let delimiter = data[cursor]
                    cursor++
                    let valueStart = cursor
                    while (cursor < data.size && data[cursor] != delimiter) { cursor++ }
                    value = part(data, valueStart, cursor)
                    if (cursor < data.size) { cursor++ }
                } else {
                    let valueStart = cursor
                    while (cursor < data.size && !isSpace(data[cursor]) && data[cursor] != 62) { cursor++ }
                    value = part(data, valueStart, cursor)
                }
            }
            attrCount++
            if (attrCount > 256) { throw Exception("HTML attribute limit exceeded") }
            if (attrCount > 1) { attributes.append(",") }
            attributes.append("{\"name\":" + quoted(attrName) + ",\"value\":" + quoted(value) + "}")
        }
        if (cursor < data.size) { cursor++ }
        if (isClose) { writer.add("{\"type\":\"close\",\"name\":" + quoted(name) + writer.range(tagStart, cursor) + "}") }
        else {
            writer.add("{\"type\":\"open\",\"name\":" + quoted(name) + ",\"attributes\":[" +
                attributes.toString() + "],\"selfClosing\":" + selfClosing.toString() + writer.range(tagStart, cursor) + "}")
            if (!selfClosing && (name == "script" || name == "style" || name == "textarea" || name == "title")) {
                rawTag = name
            }
        }
        pos = cursor
        textStart = pos
    }
    writer.text(textStart, data.size)
    return writer.finish()
}

@C
public func rulecore_tokenize(input: CString): CString {
    var result = ""
    try {
        if (input.isNull() || input.size() > MAX_INPUT) { throw Exception("Invalid HTML input") }
        result = tokenizeHtml(input.toString())
    } catch (error: Exception) {
        result = "{\"tokens\":[],\"error\":" + quoted(error.message) + "}"
    }
    return unsafe { LibC.mallocCString(result) }
}

@C
public func rulecore_free(output: CString): CString {
    unsafe { LibC.free(output) }
    return CString(CPointer<UInt8>())
}
