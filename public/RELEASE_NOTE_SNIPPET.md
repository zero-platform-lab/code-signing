## 署名について

この配布物は Zero Platform Lab の自己署名証明書で署名されています。

```
発行者    CN=Zero Platform Lab, O=Zero Platform Lab
SHA-256   97:D3:70:0C:CE:4D:0C:06:8D:B0:0E:24:60:48:17:BC:A0:AD:C9:D2:F4:4E:36:07:76:58:41:55:E3:E2:3D:E0
SHA-1     0E:70:1D:C2:53:14:3D:4E:AA:3C:1F:98:09:4A:D0:EF:10:47:5A:66
有効期限  2031-09-23
```

### 署名を確認する

PowerShell で、拇印が上と一致することを確かめてください。

```powershell
Get-AuthenticodeSignature .\<ファイル名> |
  Select-Object Status, @{n='Thumbprint';e={$_.SignerCertificate.Thumbprint}}
```

`Status` が `UnknownError` と出るのは正常です。**署名そのものは健全だが、
発行元が Windows に信頼されていない**という意味です。自己署名なのでこうなります。

`HashMismatch` や `NotSigned` が出た場合は、ファイルが壊れているか改ざんされています。
使わないでください。

### 信頼ストアへ登録する（任意）

登録すると `Status` が `Valid` になり、SmartScreen 以外の警告が減ります。
**登録は管理者権限が要り、そのアプリ以外にも影響します。** 必要な場合だけ行ってください。

```powershell
# 管理者の PowerShell で
Import-Certificate -FilePath .\signing.cer `
  -CertStoreLocation Cert:\LocalMachine\TrustedPublisher
```

ルート証明書として登録する場合は `Cert:\LocalMachine\Root` を指定します。
**その環境で、この証明書で署名された任意のコードが信頼されます。** 影響範囲を
理解したうえで判断してください。

登録を解除するには、`certmgr.msc` から該当の証明書を削除します。

### 知っておいてほしいこと

- 公開 CA による証明書ではありません。**登録していない環境では「不明な発行元」として扱われます**
- **Microsoft SmartScreen の警告は出ます。** 署名の有無とは別の仕組みで、
  ダウンロード数などの実績で判定されます
- コード署名は、配布物が改ざんされていないことと発行元が同一であることを示すだけで、
  **アプリケーションの安全性そのものを保証しません**
- 管理者権限の要求（UAC）は署名では変わりません
