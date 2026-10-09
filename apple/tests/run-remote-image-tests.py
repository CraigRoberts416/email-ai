#!/usr/bin/env python3
"""Exercise the production image pipeline on macOS with synthetic HTTPS responses.
Only the UIKit UIImage wrapper is substituted; ImageIO, tasks, cache and disk
code are production code. No mailbox, browser or real image URL is accessed.
"""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[2]
source = (root / 'apple/DecisionInbox/Services/RemoteImageStore.swift').read_text().split('struct CachedRemoteImage<', 1)[0]
source = source.replace('import UIKit', '''import CoreGraphics
final class UIImage: @unchecked Sendable {
    let cgImage: CGImage?
    init(cgImage: CGImage) { self.cgImage = cgImage }
}''')
with tempfile.TemporaryDirectory(prefix='remote-image-tests-') as folder:
    path = Path(folder)
    (path / 'RemoteImageStore.swift').write_text(source)
    binary = path / 'test'
    subprocess.run(['swiftc', '-swift-version', '5', '-parse-as-library', str(path / 'RemoteImageStore.swift'),
                    str(root / 'apple/DecisionInbox/Services/IdentityDiskCache.swift'),
                    str(root / 'apple/tests/RemoteImagePipelineTests.swift'), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=30)
