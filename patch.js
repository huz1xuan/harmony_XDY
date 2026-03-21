const fs = require('fs');
const filePath = '/Users/mac/work/harmony_XDY/entry/src/main/ets/pages/Index.ets';
const content = fs.readFileSync(filePath, 'utf-8');

// Find the section to replace
const pattern = /const newViews: PlayerViewInfo\[\] = \[\];[\s\S]*?this\.playerViews = newViews;/m;
const match = content.match(pattern);

if (match) {
  const newCode = `const views: PlayerViewInfo[] = [];
      const sw: number = this.screenWidth;
      for (const vc of list) {
        // 与Android端一致：创建所有类型的PlayerView，包括'showstage'、'invisible'、'zoom'
        // 使用与 Android 端一致的计算方式：maxWidth * percentage
        const leftPx: number = Math.ceil(sw * vc.left * 0.01);
        const topPx: number = Math.ceil(sw * vc.top * 0.01);
        const widthPx: number = Math.ceil(sw * vc.width * 0.01);
        const heightPx: number = Math.ceil(sw * vc.height * 0.01);
        const radiusPx: number = Math.ceil(sw * vc.radius * 0.01);

        const pv = new PlayerViewInfo({
          vid: vc.id,
          userId: 0, userRole: vc.userRole, userName: '',
          isPlaying: false, surfaceId: '', audioMuted: false, videoMuted: false,
          channelId: '',
          left: leftPx,
          top: topPx,
          width: widthPx,
          height: heightPx,
          radius: radiusPx,
          visible: false, volumeBtn: vc.volumeBtn, zoomBtn: vc.zoomBtn,
        });
        views.push(pv);
      }
      this.playerViews = views;`;

  const newContent = content.replace(pattern, newCode);
  fs.writeFileSync(filePath, newContent);
  console.log('Successfully patched Index.ets');
} else {
  console.log('Could not find the pattern to replace');
}
