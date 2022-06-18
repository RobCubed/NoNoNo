import std/net as net
from strutils import splitWhitespace, replace, split, toHex, strip
from std/uri import parseUri, decodeUrl, encodeUrl, decodeQuery
import std/strformat
import htmlgen
import std/tables
import std/os as os

const css = """html{
 font-family: sans-serif;
 background: #222222;
 color: #fff;
 text-align: center;
 max-width:800px;
 margin: auto;
}
a:link,a:visited{color: chocolate}
table {
 margin:auto;
 max-width: 800px;
}
tr {
 text-align: center;
 word-wrap: anywhere
}
tr > td:first-child {
 width: 10em
}"""

const opensearch = staticRead("opensearch.xml")
const bangTemplate = staticRead("bangs.txt")
const favicon = staticRead("no.ico")


var bangs: OrderedTableRef[string, string]

proc loadBangs(): void =
    bangs = newOrderedTable[string, string]()
    bangs[""] = "https://www.google.com/search?hl=en&q={q}"
    if not os.fileExists("bangs.txt"):
        writeFile("bangs.txt", bangTemplate)
    for line in lines "bangs.txt":
        let spl = splitWhitespace(line)
        case len(spl):
            of 0:
                continue
            of 1:
                bangs[""] = spl[0]
            else:
                bangs[spl[0]] = spl[1]
    bangs.sort(cmp)

proc saveBangs(): void =
    let f = open("bangs.txt", fmWrite)
    for bang, url in bangs:
        f.write(&"{bang} {url}\n")
    close(f)


proc htmlStart(content: string): string =
    return html(
        head(
            meta(charset="UTF-8"),
            link(
                rel="search",
                href="/opensearch.xml",
                type="application/opensearchdescription+xml",
                title="No!No!No!"
            ),
            title("No! No! No!"),
            style(css)
        ),
        body(
            a(href="/", "home"), hr(),
            content
        )
    )

iterator generateTable(): string =
    yield tr(th("bang"), th("url"), th("delete"))
    for bang, url in bangs:
        yield tr(td(bang), td(a(url, href=url)), td(a("❌", href= &"/deletebang?{encodeUrl(bang)}")))

proc sendHeaderOnlyResponse(client: Socket, code: int, headers: varargs[string]):void =
    send(client, &"HTTP/1.1 {code}\r\n")
    for header in headers:
        send(client, header & "\r\n")
    send(client, "\r\n")

proc sendBasicResponse(client: Socket, code: int, data: string, content_type: string, headers: varargs[string]): void =
    send(client, &"HTTP/1.1 {code}\r\n")
    send(client, &"Content-Type: {content_type}\r\n")
    for header in headers:
            send(client, header & "\r\n")

    send(client, &"Content-Length: {len(data)}\r\n\r\n")

    send(client, data)

proc sendHTML(client: Socket, code: int, data: string): void =
    sendBasicResponse(client, code, htmlStart(data), "text/html")

proc redirect(client: Socket, url: string): void =
    sendHeaderOnlyResponse(client, 301, &"Location: {url}")

proc num2hex(i: string): string =
    return toHex(len(i)).strip(leading=true, trailing=false, chars = {'0'})


proc handleSock(client: Socket): void =
    defer: client.close()
    var buf = ""
    var query: string = ""
    net.readLine(client, query)
    buf = query
    while buf != "\r\n" and buf != "":
        net.readLine(client, buf)
    var splitQuery = splitWhitespace(query)
    if len(splitQuery) != 3: return
    let parsed = parseUri(splitQuery[1])

    case parsed.path:
        of "/":

            let data = htmlStart(`div`(
                                     h3("no! no! no!"),
                                     p("custom bangs for the custom man"),
                                     a(button("reload bangs from disk"), href="/reload"),
                                     a(button("save bangs to disk"), href="/save"), br(),
                                     `form`(
                                         class="newBang",
                                         action="/newbang",
                                         p("add a new bang. in the link, '{q}' is replaced with the search query"),
                                         input(`type`="text", placeholder="!bang", name="bang"),
                                         input(`type`="text", placeholder="http://example.com/{q}", name="link"),
                                         button("add")
                                     ),
                                     table("%%%%BREAK%%%%", border="1")
                                 ))
            let split = split(data, "%%%%BREAK%%%%", 1)

            send(client, &"HTTP/1.1 200\r\n")
            send(client, &"Content-Type: text/html\r\n")
            send(client, &"Transfer-Encoding: chunked\r\n\r\n")
            send(client, &"{num2hex(split[0])}\r\n")
            send(client, split[0] & "\r\n")
            var length: string
            for chunk in generateTable():
                length = num2hex(chunk)
                send(client, &"{length}\r\n")
                send(client, &"{chunk}\r\n")
            send(client, &"{num2hex(split[1])}\r\n")
            send(client, split[1] & "\r\n")

        of "/opensearch.xml":
            sendBasicResponse(client, 200, opensearch, "application/opensearchdescription+xml")
        of "/search":
            let query = splitWhitespace(decodeUrl(parsed.query), 1)
            var q = (if len(query) == 1: "" else: query[1])
            var url = bangs[""]

            if bangs.hasKey(query[0]):
                url = bangs[query[0]]
            else:
                q = decodeUrl(parsed.query)


            redirect(client, replace(url, "{q}", encodeUrl(q)))
        of "/reload":
            loadBangs()
            client.sendHTML(200, p("reloaded bangs!"))
        of "/save":
            saveBangs()
            client.sendHTML(200, p("saved bangs to disk"))
        of "/newbang":
            var bang = ""
            var link = ""
            for k, v in decodeQuery(parsed.query):
                if k == "bang":
                    bang = v
                elif k == "link":
                    link = decodeUrl(v)
            bangs[bang] = link
            bangs.sort(cmp)
            client.sendHTML(200, p(&"added bang: '{bang}' -> '{link}'"))
        of "/deletebang":
            let bang = decodeUrl(parsed.query)
            if bang in bangs:
                bangs.del(bang)
                client.sendHTML(200, p(&"deleted bang: '{bang}'"))
            else:
                client.sendHTML(500, p(&"bang not found"))
        of "/favicon.ico":
            client.sendBasicResponse(200, favicon, "image/x-icon")
        else:
            sendHTML(client, 404, "page not found")

proc main(): void =
    let socket: Socket = net.newSocket()
    socket.bindAddr(Port(7878))
    socket.listen()

    var client_t: Socket
    while true:
        socket.accept(client_t)
        try:
            handleSock(client_t)
        except OSError:
            close(client_t)

loadBangs()
main()