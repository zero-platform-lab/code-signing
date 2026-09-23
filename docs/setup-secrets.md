# Organization Secrets の登録

証明書を作った直後と、更新したときに行う。

## 前提

`gh` に `admin:org` スコープが要る。無い場合は追加する。

```bash
gh auth refresh -h github.com -s admin:org
```

対話でブラウザが開く。Organization の管理者であること。

## 登録

`code-signing` を clone した場所で、`secrets/` が手元にある状態で実行する。

```bash
cd ~/code-signing

# 対象リポジトリ。署名を使うアプリを増やすたびにここへ足す
REPOS=code-signing

gh secret set SIGNING_PFX_BASE64 --org zero-platform-lab \
  --visibility selected --repos "$REPOS" < secrets/signing.pfx.b64

gh secret set SIGNING_PFX_PASSWORD --org zero-platform-lab \
  --visibility selected --repos "$REPOS" < secrets/signing.pfx.password

# 拇印は SHA-1 から区切りを除いた 40 文字。signtool と検証で使う
grep '^SHA-1' secrets/THUMBPRINT.txt | cut -d: -f2- | tr -d ': \n' |
  gh secret set SIGNING_THUMBPRINT --org zero-platform-lab \
    --visibility selected --repos "$REPOS"
```

**`cut -d: -f2-` を使うこと。** `sed 's/.*: *//'` は拇印に含まれるコロンまで
食ってしまい、末尾の 2 文字だけが残る。

## 確認

```bash
gh secret list --org zero-platform-lab
```

3 つが出れば登録できている。値は表示されない。

拇印だけは公開情報なので、中身を確かめてよい。

```bash
grep '^SHA-1' secrets/THUMBPRINT.txt | cut -d: -f2- | tr -d ': \n'; echo
# 40 文字の 16 進。現在: 0E701DC253143D4EAA3C1F98094AD0EF10475A66
```

## アプリを増やすとき

`--repos` に足して 3 つとも登録し直す。Web からなら
Organization → Settings → Secrets and variables → Actions で、
各 Secret の Repository access に追加する。

## 再利用可能ワークフローへの access

`code-signing` は Private なので、他リポジトリからワークフローを呼ぶには
開放が要る。

```
code-signing → Settings → Actions → General → Access
  「Accessible from repositories in the organization」を選ぶ
```

これをしないと、呼び出し側が `workflow not found` で失敗する。

## 手元の後始末

Secrets へ入れたら、手元の秘密鍵をどうするか決める。

- **退避する**: パスワード管理ソフトか暗号化した外部媒体へ。
  鍵を失うと、同じ証明書での更新ができなくなる
- **消す**: `secrets/` を削除する。以後の署名は GitHub 側だけで行われる

どちらにせよ `secrets/` は `.gitignore` で除外済みで、コミットされない。
