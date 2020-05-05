# rfid-scanner

Currently bug on IRQ pull setting. Choose pins default to pull:up for IRQ

### Dependencies

- pmount (easier mounting): `apt-get install pmount`

### Auto Login

https://askubuntu.com/questions/819117/how-can-i-get-autologin-at-startup-working-on-ubuntu-server-16-04-1#819154

`sudo systemctl edit getty@tty1.service`

```sh
[Service]
ExecStart=
ExecStart=-/sbin/agetty --noissue --autologin ubuntu %I $TERM
Type=idle
```

> Replace `ubuntu` with username

### Auto Start

Create a .service file in the systemd folder -> `/etc/systemd/system/scanner.service`.

```sh
[Unit]
Description=RFID Scanner service
After=network.target

[Service]
Type=forking
WorkingDirectory=/home/rfid-scanner
ExecStart=sudo /home/rfid-scanner/.build/release/Run
Restart=always

[Install]
WantedBy=multi-user.target
Alias=scanner.service
```

#### Control whether service loads on boot
sudo systemctl enable my_service
sudo systemctl disable my_service

#### Manual start and stop
sudo systemctl start my_service
sudo systemctl stop my_service

#### Restarting/reloading
sudo systemctl daemon-reload # Run if .service file has changed
sudo systemctl restart my_restart
