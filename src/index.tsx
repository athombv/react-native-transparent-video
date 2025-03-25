import React, { useRef } from 'react';
import {
  requireNativeComponent,
  StyleProp,
  ViewStyle,
} from 'react-native';
// @ts-ignore
import resolveAssetSource from 'react-native/Libraries/Image/resolveAssetSource';

type TransparentVideoProps = {
  style?: StyleProp<ViewStyle>;
  source?: any;
  loop?: boolean;
  autoplay?: boolean;
  onProgress?: (progress: number) => void;
};

const ComponentName = 'TransparentVideoView';
const TransparentVideoView = requireNativeComponent(ComponentName);

/**
 * TransparentVideo component for rendering a transparent video.
 */
const TransparentVideo = (props: TransparentVideoProps) => {
  const videoRef = useRef<any>(null);

  // Resolving source URI from the props
  const source = resolveAssetSource(props.source) || { uri: props.source };
  let uri = source.uri || '';

  // Adding "file://" prefix for local URIs
  if (uri && uri.match(/^\//)) {
    uri = `file://${uri}`;
  }

  // Preparing props for the native component
  const nativeProps = {
    ...props,
    ref: videoRef,
    style: props.style,
    src: { uri, type: source.type || '' },
    autoplay: props.autoplay ?? true,
    loop: props.loop ?? true,
  };

  return <TransparentVideoView {...nativeProps} />;
};

export default TransparentVideo;
