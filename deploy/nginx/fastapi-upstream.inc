upstream bridgework_fastapi_backend {
    # FastAPI 활성 슬롯은 fastapi_blue_green_switch.sh가 갱신한다.
    server 127.0.0.1:19000;
    keepalive 64;
}
