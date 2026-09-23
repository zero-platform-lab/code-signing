#!/usr/bin/env bash
#
# Zero Platform Lab のコード署名証明書を作る。
#
# **このスクリプトは手元で実行する。** 生成した秘密鍵と PFX は
# どこにもコミットしないこと。GitHub Secrets へ入れたら手元から消す。
#
# 使い方:
#   scripts/new-cert.sh              対話でパスワードを聞く
#   scripts/new-cert.sh -o out-dir   出力先を指定する
set -euo pipefail

CN="Zero Platform Lab"
DAYS=1826          # 5 年 (うるう年を1回含む)
KEY_BITS=3072      # RSA 3072 + SHA-256
OUT="./out"

usage() {
  cat <<'USAGE'
使い方: new-cert.sh [オプション]

  -o <dir>   出力先。既定は ./out
  -d <days>  有効日数。既定は 1826 (約5年)
  -g         パスワードを無作為に生成し signing.pfx.password に書く
             (端末には表示しない)
  -h         このヘルプ

パスワードは環境変数 PFX_PASSWORD でも渡せる。

出力:
  signing.key       秘密鍵。**絶対に公開しない**
  signing.crt       公開証明書 (PEM)
  signing.cer       公開証明書 (DER)。利用者に配るのはこれ
  signing.pfx       秘密鍵入り。GitHub Secrets に入れるのはこれ
  signing.pfx.b64   PFX を base64 にしたもの。Secrets へはこの中身を貼る
  signing.pfx.password  -g のときだけ。生成したパスワード
  THUMBPRINT.txt    SHA-1 と SHA-256 の拇印。公開して利用者に確認させる
USAGE
}

GEN_PASSWORD=0
while getopts 'o:d:gh' opt; do
  case "$opt" in
    o) OUT=$OPTARG ;;
    d) DAYS=$OPTARG ;;
    g) GEN_PASSWORD=1 ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done
export GEN_PASSWORD

mkdir -p "$OUT"
cd "$OUT"

if [[ -e signing.key || -e signing.pfx ]]; then
  echo "既存の鍵がある: $(pwd)" >&2
  echo "上書きすると、その鍵で署名済みの配布物を更新できなくなる。" >&2
  echo "続けるなら先に退避すること。" >&2
  exit 1
fi

# パスワードの決め方は 3 通り。いずれも端末に表示しない。
#   1. 環境変数 PFX_PASSWORD を渡す
#   2. --gen-password  無作為に生成し signing.pfx.password へ書く
#   3. 何も指定しなければ対話で聞く
if [[ "${GEN_PASSWORD:-0}" == "1" ]]; then
  PFX_PASS=$(openssl rand -base64 24 | tr -d '\n')
  printf '%s' "$PFX_PASS" > signing.pfx.password
  chmod 600 signing.pfx.password
  echo "パスワードを生成し signing.pfx.password に書いた (画面には出さない)"
elif [[ -n "${PFX_PASSWORD:-}" ]]; then
  PFX_PASS=$PFX_PASSWORD
else
  read -rsp 'PFX のパスワード: ' PFX_PASS; echo
  read -rsp '確認のためもう一度: ' PFX_PASS2; echo
  [[ "$PFX_PASS" == "$PFX_PASS2" ]] || { echo '一致しない' >&2; exit 1; }
fi
[[ ${#PFX_PASS} -ge 12 ]] || { echo 'パスワードが短い。12文字以上にすること' >&2; exit 1; }

# コード署名に必要な拡張。
#   keyUsage           digitalSignature だけあればよい
#   extendedKeyUsage   codeSigning (1.3.6.1.5.5.7.3.3)
#   basicConstraints   CA ではない
cat > ext.cnf <<EOF
[ req ]
distinguished_name = dn
prompt             = no
x509_extensions    = v3

[ dn ]
CN = $CN
O  = $CN

[ v3 ]
basicConstraints       = critical, CA:FALSE
keyUsage               = critical, digitalSignature
extendedKeyUsage       = critical, codeSigning
subjectKeyIdentifier   = hash
EOF

echo "鍵を作る (RSA $KEY_BITS)..."
openssl genrsa -out signing.key "$KEY_BITS" 2>/dev/null
chmod 600 signing.key

echo "自己署名証明書を作る (有効 $DAYS 日)..."
openssl req -new -x509 -sha256 -days "$DAYS" \
  -key signing.key -out signing.crt -config ext.cnf

echo "配布用の DER を作る..."
openssl x509 -in signing.crt -outform DER -out signing.cer

echo "PFX を作る..."
openssl pkcs12 -export -out signing.pfx \
  -inkey signing.key -in signing.crt \
  -name "$CN" -passout "pass:$PFX_PASS"
chmod 600 signing.pfx

base64 -w0 signing.pfx > signing.pfx.b64
chmod 600 signing.pfx.b64

{
  echo "Subject : $(openssl x509 -in signing.crt -noout -subject | sed 's/^subject=//')"
  echo "有効期限: $(openssl x509 -in signing.crt -noout -enddate | sed 's/^notAfter=//')"
  echo
  echo "SHA-256 : $(openssl x509 -in signing.crt -noout -fingerprint -sha256 | sed 's/.*=//')"
  echo "SHA-1   : $(openssl x509 -in signing.crt -noout -fingerprint -sha1   | sed 's/.*=//')"
} > THUMBPRINT.txt

rm -f ext.cnf

cat <<EOF

作成した: $(pwd)

$(cat THUMBPRINT.txt)

次にやること
  1. GitHub の Organization Secrets に登録する
       SIGNING_PFX_BASE64    <- signing.pfx.b64 の中身
       SIGNING_PFX_PASSWORD  <- いま入れたパスワード
       SIGNING_THUMBPRINT    <- 上の SHA-1 から区切りを除いた 40 文字
                                grep '^SHA-1' THUMBPRINT.txt | cut -d: -f2- | tr -d ': \n'

     手順は docs/setup-secrets.md にまとめてある。
     admin:org スコープが要る (gh auth refresh -h github.com -s admin:org)

  2. signing.cer を公開用リポジトリか Release に置く

  3. **signing.key / signing.pfx / signing.pfx.b64 を手元から消す**
     鍵を失うと更新できなくなるので、消す前に安全な場所へ退避すること
     (パスワード管理ソフト、暗号化した外部媒体など)
EOF
