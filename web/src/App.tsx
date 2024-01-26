import { Suspense, useEffect, useState, StrictMode } from 'react';

import './App.css';
import { Canvas, Euler, Vector3 } from '@react-three/fiber';

import { a as web } from '@react-spring/web';
import { Model } from './Iask';
import icon from './assets/icon.png';
import download from './assets/download.svg';
import downloadMac from './assets/download-mac.svg';
import { createBrowserRouter, RouterProvider } from 'react-router-dom';

function Home() {
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

const router = createBrowserRouter([
  {
    path: '/',
    element: <Home />,
  },
  {
    path: '/privacy',
    element: <PrivacyPolicy />,
  },
]);

function App() {
  return (
    <StrictMode>
      <RouterProvider router={router} />
    </StrictMode>
  );
}

export default App;

function PrivacyPolicy() {
  return (
    <>
      <div style={{ padding: 20 }}>
        <h1>iAsk Privacy Policy</h1>
        <p>Last Updated: 1/26/24</p>

        <h2>1. Introduction</h2>
        <p>
          Welcome to iAsk! Your privacy is important to us. This Privacy Policy
          explains how we collect, use, disclose, and safeguard your information
          when you use our iAsk app. Please read this policy carefully to
          understand our practices regarding your information and how we will
          treat it.
        </p>

        <h2>2. Information Collection</h2>
        <ul>
          <li>
            <strong>Personal Information:</strong> We do not to collect any
            personal information.
          </li>
          <li>
            <strong>Usage Data:</strong> We do not collect any usage data.
          </li>
          <li>
            <strong>Device Information:</strong> We do not collect any device
            information.
          </li>
          <li>
            <strong>External API Usage:</strong> We use OpenAI's Enterprise
            Level GPT-4 API to answer questions. This API comes OpenAI's privacy
            policy which can be found{' '}
            <a href="https://openai.com/policies/business-terms">here</a>.
          </li>
        </ul>
      </div>
    </>
  );
}

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
        <div
          style={{
            display: 'flex',
            flexDirection: 'row',
          }}
        >
          <a href="https://apple.com">
            <img src={download} style={{ height: 40, width: 'auto' }} />
          </a>
          <a href="https://apple.com" style={{ marginLeft: 10 }}>
            <img src={downloadMac} style={{ height: 40, width: 'auto' }} />
          </a>
        </div>
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
