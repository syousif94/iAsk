import { Suspense, useEffect, useState } from 'react';

import './App.css';
import { Canvas, Euler, Vector3 } from '@react-three/fiber';

import { a as web } from '@react-spring/web';
import { Model } from './Iask';
import icon from './assets/icon.png';
import download from './assets/download.svg';

function App() {
  return (
    <>
      <web.main className="main">
        <Canvas camera={{ position: [0, 0, -30], fov: 35 }}>
          <ambientLight intensity={1.5} />
          <PhoneModel />

          {/* <Orbit /> */}
        </Canvas>
      </web.main>
      <Overlay />
    </>
  );
}

export default App;

function PhoneModel() {
  const [position, setPosition] = useState<Vector3>([6, 0, 0]);
  const [rotation, setRotation] = useState<Euler>([0, Math.PI * 0.1, 0]);

  useEffect(() => {
    function handleResize() {
      if (window.innerWidth < 500) {
        setPosition([-2, 0, 0]);
        setRotation([Math.PI * 0.05, Math.PI * -0.05, Math.PI * 0.02]);
      } else if (window.innerWidth < 768) {
        setPosition([-6, 0, 0]);
        setRotation([Math.PI * -0.1, Math.PI * -0.1, 0]);
      } else {
        setPosition([6, 0, 0]);
        setRotation([Math.PI * -0.05, Math.PI * 0.1, 0]);
      }
    }

    // Set the position on initial load
    handleResize();

    // Add event listener
    window.addEventListener('resize', handleResize);

    // Remove event listener on cleanup
    return () => window.removeEventListener('resize', handleResize);
  }, []);

  return (
    <Suspense fallback={null}>
      <Model position={position} rotation={rotation} />
    </Suspense>
  );
}

function Overlay() {
  return (
    <div className="overlay">
      <div className="overlay__content">
        <img src={icon} style={{ height: 100, width: 100, borderRadius: 25 }} />
        <h1>Introducing iAsk</h1>
        <div>The smarter assistant</div>
        <ul>
          <li>
            Answer questions about any of your files and links, including pdfs,
            office (xslx, doc, ppt), images, and code.
          </li>
          <li>
            Fully encrypted and private (SOC2/3 compliant). None of your files
            leave your device. Your data cannot be accessed or used to train on.
          </li>
          <li>
            Integrates with your calendar, reminders, and contacts to facilitate
            easy creation with your voice, camera, and images.
          </li>
        </ul>

        <div style={{ height: 20 }} />
        <a href="https://apple.com">
          <img src={download} style={{ height: 60, width: 'auto' }} />
        </a>

        <p>Available on all your Apple devices for just $4.99 a month.</p>
        <p>14 day free trial included.</p>
        <p>
          Source available on{' '}
          <a href="https://github.com/syousif94/iAsk">Github</a>.
        </p>
        <div style={{ height: 20 }} />
      </div>
    </div>
  );
}
