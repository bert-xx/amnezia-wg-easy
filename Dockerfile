# --- Стадия 1: Компилируем amneziawg-go из исходников ---
FROM alpine AS build-go
RUN apk add --no-cache git go make
RUN git clone https://github.com/amnezia-vpn/amneziawg-go.git
RUN cd amneziawg-go && make

# --- Стадия 2: Компилируем утилиты wg и wg-quick из исходников ---
FROM alpine AS build-c
RUN apk add --no-cache git build-base linux-headers
RUN git clone https://github.com/amnezia-vpn/amneziawg-tools.git
RUN cd amneziawg-tools/src && make

# --- Стадия 3: Собираем веб-интерфейс панели ---
FROM node:20-alpine AS build-node
WORKDIR /build
COPY . .
RUN npm ci --omit=dev

# --- Стадия 4: Финальный запускной контейнер на чистом Alpine ---
FROM alpine AS run
RUN apk add --no-cache bash nodejs dpkg iptables iptables-legacy dumb-init

# Настраиваем совместимость iptables для работы на ядрах Oracle Cloud
RUN update-alternatives \
  --install /usr/sbin/iptables iptables /usr/sbin/iptables-legacy 10 \
  --slave /usr/sbin/iptables-restore iptables-restore /usr/sbin/iptables-legacy-restore \
  --slave /usr/sbin/iptables-save iptables-save /usr/sbin/iptables-legacy-save || true

# Копируем скомпилированные на прошлых шагах бинарники AmneziaWG
COPY --from=build-go /amneziawg-go/amneziawg-go /usr/local/bin
COPY --from=build-c /amneziawg-tools/src/wg /usr/local/bin
COPY --from=build-c /amneziawg-tools/src/wg-quick/linux.bash /usr/local/bin/wg-quick

# Настраиваем симлинки и пути для AmneziaWG
RUN mkdir -p /etc/amnezia && ln -s /etc/wireguard /etc/amnezia/amneziawg
RUN ln -s wg /usr/local/bin/awg

# Копируем готовую веб-панель из вашего репозитория
COPY --from=build-node /build/src /app
WORKDIR /app

ENV DEBUG=Server,WireGuard

# Запускаем через нативный dumb-init
ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["node", "server.js"]
