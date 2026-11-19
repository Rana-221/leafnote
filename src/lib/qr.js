import qrcode from 'qrcode-generator'

export function makeQrSvg(text) {
  const qr = qrcode(0, 'M')
  qr.addData(String(text), 'Byte')
  qr.make()
  return qr.createSvgTag({ cellSize: 4, margin: 4, scalable: true })
}
