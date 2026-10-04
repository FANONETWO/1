<#
轮回回廊 · 全量测试运行器（带超时）
================================================================
为什么需要它（血泪教训）：
  项目的 `-s` 单测一旦出现**编译错误**（例如引用了 -s 模式下不存在的 autoload
  `DebugLog`），Godot 不会退出 —— 脚本编译失败 → `quit()` 永远不执行 →
  进程永久挂住、整批测试再也跑不完，而且因为 stdout 被缓冲，连错误都看不到。
  这个脚本对每个测试单独设超时：挂住的会被杀掉并标 TIMEOUT，同时把引擎报错摘出来。

用法（在项目根目录）：
  pwsh -File tools/run_tests.ps1                   # 单测 + 场景测试（全量）
  pwsh -File tools/run_tests.ps1 -UnitsOnly        # 只跑纯逻辑单测
  pwsh -File tools/run_tests.ps1 -ScenesOnly       # 只跑场景/流程测试
  pwsh -File tools/run_tests.ps1 -TimeoutSec 120   # 放宽容错时间
#>
param(
	[string]$Godot = "D:\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe",
	[int]$TimeoutSec = 90,
	[string]$LogDir = "$env:TEMP\loop_tests",
	[switch]$UnitsOnly,
	[switch]$ScenesOnly
)

$proj = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path $Godot)) {
	Write-Host "找不到 Godot 可执行文件：$Godot" -ForegroundColor Red
	exit 2
}
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }

# 单测：`-s` 跑（无 autoload，必须是纯逻辑）
$units = @(
	"dice_test", "combat_test", "content_test", "world_test",
	"bloodline_test", "bloodline_combat_test", "bloodline_mitigation_test",
	"attr_redesign_test", "los_test", "rooms_test", "action_bar_test"
)
# 场景测试：`.tscn` 跑（有 autoload，端到端）
$scenes = @(
	"flow_driver", "ui_flow_driver", "real_flow_test", "click_test",
	"scenario_entities_test", "kill_removal_test", "battle_rules_test",
	"combat_return_test", "item_heal_test", "bloodline_live_test",
	"bloodline_skill_test", "room_walk_test", "stealth_test", "stealth_engage_test",
	"noise_test", "patrol_test", "persist_test", "flee_test", "pace_test",
	"audio_test", "ux_test", "mode_test", "team_battle_test", "vision_test"
)

$results = @()

function Invoke-OneTest {
	param([string]$Name, [string[]]$GodotArgs, [int]$Limit)

	$out = Join-Path $LogDir "$Name.out.txt"
	$err = Join-Path $LogDir "$Name.err.txt"
	Remove-Item $out, $err -ErrorAction SilentlyContinue

	$startedAt = Get-Date
	$sw = [System.Diagnostics.Stopwatch]::StartNew()
	$p = Start-Process -FilePath $Godot -ArgumentList $GodotArgs -WorkingDirectory $proj `
		-RedirectStandardOutput $out -RedirectStandardError $err -PassThru -NoNewWindow
	$exited = $p.WaitForExit($Limit * 1000)
	$sw.Stop()
	$sec = [int]$sw.Elapsed.TotalSeconds

	$stdout = if (Test-Path $out) { Get-Content $out -Raw -Encoding UTF8 } else { "" }
	$stderr = if (Test-Path $err) { Get-Content $err -Raw -Encoding UTF8 } else { "" }

	if (-not $exited) {
		try { $p.Kill() } catch { }
		$hint = ($stderr -split "`n" | Where-Object { $_ -match "SCRIPT ERROR|Parse Error|Identifier not found|at: " } | Select-Object -First 4) -join "`n    "
		return [pscustomobject]@{ Test = $Name; Status = "TIMEOUT"; Sec = $sec; Started = $startedAt.ToString("HH:mm:ss"); Note = $hint }
	}

	if ($stderr -match "Parse Error|Compile Error|Identifier not found") {
		$hint = ($stderr -split "`n" | Where-Object { $_ -match "SCRIPT ERROR|Parse Error|Compile Error|Identifier not found|at: " } | Select-Object -First 4) -join "`n    "
		return [pscustomobject]@{ Test = $Name; Status = "ERROR"; Sec = $sec; Started = $startedAt.ToString("HH:mm:ss"); Note = $hint }
	}
	if ($stdout -match "_test: PASS" -or ($stdout -match "PASS" -and $stdout -notmatch "FAIL")) {
		return [pscustomobject]@{ Test = $Name; Status = "PASS"; Sec = $sec; Started = $startedAt.ToString("HH:mm:ss"); Note = "" }
	}
	# 有些流程测试用中文收尾（例如 flow_driver 的「端到端冒烟通过」）
	if (($stdout -match "通过" -or $stdout -match "全绿") -and $stdout -notmatch "FAIL|错误|失败") {
		return [pscustomobject]@{ Test = $Name; Status = "PASS"; Sec = $sec; Started = $startedAt.ToString("HH:mm:ss"); Note = "" }
	}
	$hint = ($stdout -split "`n" | Where-Object { $_ -match "FAIL|错误|失败|未通过" } | Select-Object -First 5) -join "`n    "
	if (-not $hint) {
		$tail = (($stdout -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 3) -join " / ")
		$hint = "无 PASS 标记（退出码 $($p.ExitCode)）：$tail"
	}
	return [pscustomobject]@{ Test = $Name; Status = "FAIL"; Sec = $sec; Started = $startedAt.ToString("HH:mm:ss"); Note = $hint }
}

if (-not $ScenesOnly) {
	foreach ($t in $units) {
		if (-not (Test-Path (Join-Path $proj "tests/$t.gd"))) { continue }
		$r = Invoke-OneTest -Name $t -GodotArgs @("--headless", "--path", $proj, "-s", "res://tests/$t.gd") -Limit $TimeoutSec
		$results += $r
		Write-Host ("[{0,-7}] {1,-28} {2,4}s  {3}" -f $r.Status, $r.Test, $r.Sec, $r.Started)
		if ($r.Note) { Write-Host ("    " + $r.Note) -ForegroundColor DarkYellow }
	}
}
if (-not $UnitsOnly) {
	foreach ($t in $scenes) {
		if (-not (Test-Path (Join-Path $proj "tests/$t.tscn"))) { continue }
		# --quit-after 只是保险丝：所有测试都会自己 quit。
		# 给得足够大，否则像 bloodline_live_test（要真实等待 40 秒）会被提前截断。
		$r = Invoke-OneTest -Name $t -GodotArgs @("--headless", "--path", $proj, "res://tests/$t.tscn", "--quit-after", "20000") -Limit $TimeoutSec
		$results += $r
		Write-Host ("[{0,-7}] {1,-28} {2,4}s  {3}" -f $r.Status, $r.Test, $r.Sec, $r.Started)
		if ($r.Note) { Write-Host ("    " + $r.Note) -ForegroundColor DarkYellow }
	}
}

$bad = @($results | Where-Object { $_.Status -ne "PASS" })
Write-Host ""
Write-Host ("===== 共 {0} 项：PASS {1} / 异常 {2} =====" -f $results.Count, ($results.Count - $bad.Count), $bad.Count)
if ($bad.Count -gt 0) {
	Write-Host ("异常项：" + (($bad | ForEach-Object { "$($_.Test)($($_.Status))" }) -join "、")) -ForegroundColor Red
	Write-Host "详细日志：$LogDir" -ForegroundColor DarkYellow
	exit 1
}
Write-Host "全绿 ✓" -ForegroundColor Green
exit 0
