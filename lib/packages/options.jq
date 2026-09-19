def strings: type == "array" and all(.[]; type == "string" and test("\\S"));
def allowed($keys): (keys - $keys | length) == 0;
type == "object" and allowed(["npm","pip","dotnet","psresource","uv","vscode"]) and
all(.[]; type == "object") and
((.npm // {}) | length == 0) and
((.pip // {}) | allowed(["user","topLevel"]) and all(.[]; type == "boolean")) and
((.dotnet // {}) | allowed(["name"]) and
    (if has("name") then .name | type == "string" and length > 0 else true end)) and
((.uv // {}) | allowed(["scope","topLevel"]) and
    (if has("scope") then .scope | . == "All" or . == "Packages" or . == "Tools" else true end) and
    (if has("topLevel") then .topLevel | type == "boolean" else true end)) and
((.vscode // {}) | allowed(["profiles"]) and
    (if has("profiles") then .profiles | strings else true end)) and
((.psresource // {}) | allowed(["roots","name","exclude","repository"]) and
    (if has("roots") then .roots | strings else true end) and
    (if has("name") then .name | strings else true end) and
    (if has("exclude") then .exclude | strings else true end) and
    (if has("repository") then .repository | type == "string" and test("\\S") else true end))
