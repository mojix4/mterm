// Termius-style command prediction: history first, then the user's snippets,
// then a built-in list of common Linux / VPS commands.

const commonCommands = <String>[
  // packages
  'apt update', 'apt upgrade', 'apt upgrade -y', 'apt update && apt upgrade -y', 'apt install ', 'apt install -y ',
  'apt remove ', 'apt autoremove -y', 'apt list --upgradable', 'apt search ',
  'dnf update', 'dnf install ', 'yum update', 'yum install ', 'snap install ',
  // services
  'systemctl status ', 'systemctl restart ', 'systemctl stop ', 'systemctl start ', 'systemctl enable ',
  'systemctl disable ', 'systemctl daemon-reload', 'systemctl --failed', 'systemctl list-units --type=service',
  'journalctl -u ', 'journalctl -xe', 'journalctl -f', 'service --status-all',
  // files
  'ls', 'ls -la', 'ls -lh', 'cd ', 'cd ..', 'cd ~', 'pwd', 'cat ', 'less ', 'nano ', 'vim ', 'vi ', 'touch ',
  'mkdir -p ', 'rm ', 'rm -rf ', 'cp -r ', 'mv ', 'chmod +x ', 'chmod 755 ', 'chown -R ', 'ln -s ',
  'find / -name ', 'grep -r ', 'tail -f ', 'tail -n 100 ', 'head -n 20 ', 'du -sh *', 'du -sh ', 'wc -l ',
  'tar -xzf ', 'tar -czf ', 'unzip ', 'zip -r ', 'wget ', 'curl -O ', 'curl -I ', 'curl ifconfig.me',
  // system
  'df -h', 'free -h', 'uptime', 'top', 'htop', 'ps aux', 'ps aux | grep ', 'kill -9 ', 'pkill ', 'killall ',
  'uname -a', 'hostnamectl', 'lsb_release -a', 'cat /etc/os-release', 'whoami', 'history', 'clear', 'exit',
  'reboot', 'shutdown -h now', 'timedatectl', 'date', 'crontab -e', 'crontab -l', 'passwd', 'sudo su',
  'adduser ', 'usermod -aG sudo ', 'lscpu', 'lsblk', 'nproc',
  // network
  'ip a', 'ip addr', 'ip route', 'ss -tulpn', 'netstat -tulpn', 'ping ', 'ping -c 4 ', 'traceroute ',
  'nslookup ', 'dig ', 'ufw status', 'ufw allow ', 'ufw deny ', 'ufw enable', 'ufw disable', 'ufw reload',
  'iptables -L -n', 'speedtest', 'ssh ', 'scp ', 'rsync -avz ', 'nload', 'iftop', 'vnstat',
  // docker
  'docker ps', 'docker ps -a', 'docker images', 'docker logs -f ', 'docker exec -it ', 'docker restart ',
  'docker stop ', 'docker start ', 'docker rm ', 'docker rmi ', 'docker pull ', 'docker system prune -a',
  'docker compose up -d', 'docker compose down', 'docker compose logs -f', 'docker compose pull',
  'docker compose restart',
  // panels / vpn
  'x-ui', 'x-ui restart', 'x-ui status', 'x-ui log', 'marzban', 'marzban restart', 'marzban logs',
  'marzban update', 'nginx -t', 'systemctl reload nginx', 'certbot --nginx', 'certbot renew',
  // git
  'git status', 'git pull', 'git clone ', 'git log --oneline', 'git add .', 'git commit -m ', 'git push',
];

/// Up to [max] completions for the text typed so far. History beats snippets,
/// which beat the built-in list; prefix matches beat "contains" matches.
List<String> suggestCommands(String? typed, Iterable<String> history, Iterable<String> snippets,
    {int max = 4}) {
  final q = typed;
  if (q == null || q.trim().isEmpty) return const [];
  final pool = [...history, ...snippets, ...commonCommands];
  final out = <String>[];
  void add(String c) {
    final t = c.trimRight();
    if (t.isEmpty || t == q.trimRight() || out.any((o) => o.trimRight() == t)) return;
    out.add(c);
  }

  for (final c in pool) {
    if (out.length >= max) return out;
    if (c.startsWith(q)) add(c);
  }
  if (q.length >= 2) {
    final ql = q.toLowerCase();
    for (final c in pool) {
      if (out.length >= max) break;
      if (c.toLowerCase().startsWith(ql) || c.toLowerCase().contains(' $ql')) add(c);
    }
  }
  return out;
}
