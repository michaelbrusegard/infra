{lib}: rec {
  isValidLuaIdentifier = s: let
    firstChar = builtins.substring 0 1 s;
    validFirst = builtins.match "[a-zA-Z_]" firstChar != null;
    rest = builtins.substring 1 (-1) s;
    validRest = builtins.match "[a-zA-Z0-9_]*" rest != null;
  in
    validFirst && validRest && s != "";

  isUnkeyed = k: lib.hasPrefix "__unkeyed" k;

  toLua = val:
    if lib.isBool val
    then
      (
        if val
        then "true"
        else "false"
      )
    else if val == null
    then "nil"
    else if lib.isInt val
    then toString val
    else if lib.isString val
    then "\"${lib.escape ["\\" "\""] val}\""
    else if lib.isList val
    then "{${lib.concatStringsSep ", " (map toLua val)}}"
    else if lib.isAttrs val
    then
      if val ? _type && val._type == "lua-inline"
      then val.expr
      else "{${lib.concatStringsSep ", " (lib.mapAttrsToList (
          k: v:
            if isUnkeyed k
            then toLua v
            else let
              keyStr =
                if isValidLuaIdentifier k
                then k
                else ''["${k}"]'';
            in "${keyStr} = ${toLua v}"
        )
        val)}}"
    else builtins.toJSON val;

  mkLuaInline = expr: {
    _type = "lua-inline";
    inherit expr;
  };
}
