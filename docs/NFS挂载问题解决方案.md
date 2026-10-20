# NFS 挂载问题解决方案

## 快速诊断

遇到挂载失败时，按以下步骤排查：

| 报错信息 | 根因 | 解决 |
|---------|------|------|
| `access denied` | exports 限制了来源 IP，端口转发后源 IP 变了 | 用 `*` 代替具体 IP 段 |
| `Connection refused` | NFS 服务未真正监听端口（锁文件权限问题 / 服务未启动） | 修复 `/var/lib/nfs/` 权限，重启服务 |
| 挂载没反应 / 超时 | 缺少端口 111 转发 | 加 rpcbind 端口 111 转发 |
| `Connection refused` 且端口转发正常 | WSL IP 变了 | 更新端口转发地址 |

---

## 报错一：access denied

```
mount.nfs: access denied by server while mounting 192.168.1.x:/home/<用户名>/rk3588_nfs
```

### 原因

`/etc/exports` 中限制了来源 IP（如 `192.168.1.0/24`），但端口转发后实际源 IP 是 Windows 本机，不匹配 exports 中的 IP 范围。

### 解决

把 exports 中的 IP 限制改为 `*`（允许所有来源）：

```bash
echo "/home/<用户名>/rk3588_nfs *(rw,sync,no_subtree_check,no_root_squash,insecure)" | sudo tee /etc/exports
sudo exportfs -ra
sudo service nfs-kernel-server restart
```

---

## 报错二：Connection refused

```
mount.nfs: Connection refused for 192.168.1.x:/home/<用户名>/rk3588_nfs on /mnt
```

### 原因

**`/var/lib/nfs/.etab.lock` 权限错误**，导致 `exportfs` 无法正常工作。NFS 服务虽然显示 `active`，但文件系统没有被真正导出，端口 2049 未监听。

验证方法：

```bash
# 查看 exportfs 是否有权限报错
sudo exportfs -v
# 如果输出包含：could not open /var/lib/nfs/.etab.lock for locking: errno 13 (Permission denied)
# 则确认是该问题

# 检查端口是否在监听
ss -tlnp | grep 2049
# 如果没有输出，说明 NFS 没有真正绑定端口
```

### 解决

```bash
# 修复锁文件权限
sudo chown -R root:root /var/lib/nfs/
sudo chmod 755 /var/lib/nfs/
sudo rm -f /var/lib/nfs/.etab.lock /var/lib/nfs/etab /var/lib/nfs/xtab /var/lib/nfs/rmtab

# 重新配置并导出
echo "/home/<用户名>/rk3588_nfs *(rw,sync,no_subtree_check,no_root_squash,insecure)" | sudo tee /etc/exports
sudo exportfs -ra
sudo service rpcbind restart
sudo service nfs-kernel-server restart

# 验证
sudo exportfs -v
ss -tlnp | grep 2049   # 应能看到端口在监听
```

---

## 报错三：Connection refused（2049监听正常但111挂了）

**症状**：2049 端口正常监听，WSL IP 没变，端口转发也对着，但板子挂载仍报 Connection refused。

### 原因

**rpcbind 服务虽然显示 running，但 111 端口已不响应**。从 Windows 测试 `172.29.x.x:111` 不通，而 2049 端口正常。

### 验证

```powershell
# 在 Windows PowerShell 测试端口
powershell -Command "
try { $tcp = New-Object Net.Sockets.TcpClient; $tcp.Connect('172.29.155.xx', 111); Write-Host '111 OK'; $tcp.Close() }
catch { Write-Host '111 FAIL' }
"
```

### 解决

```bash
# WSL 内重启 rpcbind
wsl -d Ubuntu-24.04 -u root -- bash -c "systemctl restart rpcbind && ss -tlnp | grep 111"
```

然后重置端口转发：

```powershell
netsh interface portproxy reset
netsh interface portproxy add v4tov4 listenport=2049 listenaddress=192.168.1.x connectaddress=172.29.155.xx connectport=2049
netsh interface portproxy add v4tov4 listenport=111 listenaddress=192.168.1.x connectaddress=172.29.155.xx connectport=111
```

> WSL IP 用 `wsl -d Ubuntu-24.04 -- hostname -I` 获取

### 防火墙（111 规则可能缺失）

```powershell
netsh advfirewall firewall show rule name="NFS_WSL_111"
# 如果没有，添加：
netsh advfirewall firewall add rule name="NFS_WSL_111" dir=in action=allow protocol=TCP localport=111
```

---

## 一键修复脚本

### WSL 侧（修复 NFS 服务端）

```bash
wsl -d Ubuntu-24.04 -- bash /mnt/e/1/fix_nfs.sh
```

脚本文件：`E:\1\fix_nfs.sh`

### Windows 侧（修复端口转发 + 防火墙）

以**管理员**打开 PowerShell：

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
powershell -File E:\1\fix_nfs_portproxy.ps1
```

脚本文件：`E:\1\fix_nfs_portproxy.ps1`

---

## 板子挂载命令

```bash
ls /mnt/   # 验证
```

---

## 手动排查清单

按顺序逐项检查：

1. **WSL NFS 服务状态**
   ```bash
   wsl -d Ubuntu-24.04 -- service nfs-kernel-server status
   wsl -d Ubuntu-24.04 -- service rpcbind status
   ```

2. **exports 配置**
   ```bash
   wsl -d Ubuntu-24.04 -- cat /etc/exports
   wsl -d Ubuntu-24.04 -- sudo exportfs -v
   ```

3. **端口监听**
   ```bash
   wsl -d Ubuntu-24.04 -- ss -tlnp | grep -E "2049|111"
   ```

4. **WSL IP**
   ```bash
   wsl -d Ubuntu-24.04 -- hostname -I
   ```

5. **Windows 端口转发**
   ```powershell
   netsh interface portproxy show all
   ```

6. **防火墙**
   ```powershell
   netsh advfirewall firewall show rule name="NFS_WSL"
   netsh advfirewall firewall show rule name="NFS_WSL_111"
   ```
