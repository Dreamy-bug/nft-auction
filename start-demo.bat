@echo off
setlocal
set PATH=%USERPROFILE%\.foundry\bin;%PATH%
cd /d e:\remote\solidity\nft-auction

echo ============================================
echo    NFT Auction 本地演示一键启动
echo ============================================
echo.

REM 1. 检查 anvil 是否已在运行
cast block-number --rpc-url http://127.0.0.1:8545 >nul 2>&1
if %errorlevel%==0 (
    echo [1/3] anvil 已在运行，跳过启动与部署
    goto :frontend
)

echo [1/3] 启动 anvil (新窗口)...
start "anvil - NFT auction" anvil --chain-id 31337 --accounts 4
timeout /t 2 /nobreak >nul

echo [2/3] 部署合约到 anvil...
forge script script/DeployLocal.s.sol --tc DeployLocal --rpc-url http://127.0.0.1:8545 --broadcast --sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
if %errorlevel% neq 0 (
    echo.
    echo *** 部署失败，请检查上方输出 ***
    pause
    exit /b 1
)

:frontend
echo [3/3] 启动前端静态服务 (新窗口)...
start "frontend - NFT auction" cmd /c "cd /d e:\remote\solidity\nft-auction\frontend && python -m http.server 8080"
timeout /t 1 /nobreak >nul

echo.
echo ============================================
echo   全部启动完成！
echo   anvil:   http://127.0.0.1:8545  (chainId 31337)
echo   前端:    http://localhost:8080
echo.
echo   浏览器打开  http://localhost:8080  开始使用
echo   关闭弹出的 anvil / frontend 窗口即可停止服务
echo ============================================
echo.
pause
