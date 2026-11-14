-- 通用图例（M2-PLAN §2.1）。模板里的字母留给道具，由模板自己的 legend 覆盖。
return {
  symbols = {
    ["#"] = { kind = "wall" },
    ["="] = { kind = "wall", inner = true },
    ["."] = { kind = "floor" },
    [","] = { kind = "outdoor" },
    ["+"] = { kind = "door", inner = true },
    ["D"] = { kind = "door" },
    ["w"] = { kind = "window" },
    [" "] = { kind = "void" },
  },
}
