# apps/web

React + TypeScript + Vite + Ant Design teacher workspace created by `A003`.

Run:

```powershell
.\tools\start-local-web.ps1
```

The repo-level helper keeps Vite on `http://127.0.0.1:5173/`, writes PID/logs under `logs/dev-web/`, and supports `-Status`, `-Restart`, and `-Stop`.

Build:

```powershell
npm run build --prefix apps/web
```

The P0 shell intentionally exposes only the four ordinary teacher entries: 导入试卷、找题组卷、导入成绩、查看分析. Advanced settings remain out of the default view.
