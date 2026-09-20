import React, { useEffect, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { motion, MotionConfig, useReducedMotion } from 'motion/react';
import { AnimateNumber } from 'motion-plus/react';
import { gsap } from 'gsap';
import './style.css';

const preciseSpring = { type: 'spring', stiffness: 260, damping: 26 };

function RuntimeLab() {
  const systemReduced = useReducedMotion();
  const [forceReduced, setForceReduced] = useState(false);
  const reduced = forceReduced || systemReduced;
  const [moved, setMoved] = useState(false);
  const [springStatus, setSpringStatus] = useState('Ready');
  const [reversed, setReversed] = useState(false);
  const [count, setCount] = useState(7);
  const [timelineStatus, setTimelineStatus] = useState('Ready');
  const stage = useRef(null);
  const timeline = useRef(null);
  const items = reversed ? ['C', 'B', 'A'] : ['A', 'B', 'C'];

  useEffect(() => {
    const context = gsap.context(() => {
      timeline.current = gsap.timeline({
        paused: true,
        onComplete: () => setTimelineStatus('Complete'),
      })
        .to('.timeline-object', { x: 110, duration: 0.35, ease: 'power2.inOut' })
        .to('.timeline-object', { rotation: 90, duration: 0.25, ease: 'power2.out' })
        .to('.timeline-object', { x: 0, rotation: 0, duration: 0.35, ease: 'power2.inOut' });
    }, stage);
    return () => { timeline.current = null; context.revert(); };
  }, []);

  useEffect(() => {
    if (reduced) {
      timeline.current?.pause(0);
      setTimelineStatus('Ready · reduced motion');
    }
  }, [reduced]);

  return (
    <MotionConfig reducedMotion={reduced ? 'always' : 'never'}>
      <main>
        <header>
          <p className="eyebrow">Decision Inbox · development only</p>
          <h1>Motion, made tangible.</h1>
          <p className="lede">Three small runtime checks. Synthetic content. No connection to your mail or native app.</p>
          <label className="toggle">
            <input type="checkbox" checked={forceReduced} onChange={event => setForceReduced(event.target.checked)} />
            Preview reduced motion
          </label>
          <p className="mode" aria-live="polite">Mode: {reduced ? 'Reduced motion' : 'Full motion'}</p>
        </header>

        <section aria-labelledby="motion-title">
          <div className="section-heading"><span className="step">01</span><h2 id="motion-title">Spring & layout</h2><span className="tool">Motion</span></div>
          <p>The same object moves to its target; the same items keep their identity when their order changes.</p>
          <div className="spring-track">
            <motion.div className="spring-object" data-testid="spring-object" initial={false}
              animate={{ x: moved ? 140 : 0 }}
              transition={reduced ? { duration: 0 } : preciseSpring}
              onAnimationComplete={() => setSpringStatus('Settled')}>
              <span>●</span>
            </motion.div>
          </div>
          <div className="button-row">
            <button onClick={() => { setSpringStatus('Moving'); setMoved(value => !value); }}>Move spring</button>
            <output aria-live="polite">Spring: {springStatus}</output>
          </div>
          <div className="layout-row" aria-label="Layout items">
            {items.map(item => <motion.div layout key={item} className="layout-item"
              transition={reduced ? { duration: 0 } : preciseSpring}>{item}</motion.div>)}
          </div>
          <button onClick={() => setReversed(value => !value)}>Reverse layout</button>
        </section>

        <section aria-labelledby="premium-title">
          <div className="section-heading"><span className="step">02</span><h2 id="premium-title">State-driven number</h2><span className="tool">Motion+</span></div>
          <p>An installed premium component follows an actual React value. Reduced motion renders that value without rolling digits.</p>
          <div className="number" data-testid="premium-number" aria-label={`Current count: ${count}`}>
            {reduced ? <span>{count}</span> : <AnimateNumber transition={preciseSpring}>{count}</AnimateNumber>}
          </div>
          <div className="button-row">
            <button onClick={() => setCount(value => value + 1)}>Increment premium counter</button>
            <output>Count target: {count}</output>
          </div>
        </section>

        <section aria-labelledby="gsap-title" ref={stage}>
          <div className="section-heading"><span className="step">03</span><h2 id="gsap-title">A deliberate sequence</h2><span className="tool">GSAP</span></div>
          <p>Move, turn, return. A small timeline with cleanup when this view unmounts.</p>
          <div className="timeline-track"><div className="timeline-object" data-testid="timeline-object" /></div>
          <div className="button-row">
            <button onClick={() => {
              if (reduced) { timeline.current?.pause(0); setTimelineStatus('Complete · reduced motion'); }
              else { setTimelineStatus('Running'); timeline.current?.restart(); }
            }}>Play timeline</button>
            <output aria-live="polite">Timeline: {timelineStatus}</output>
          </div>
        </section>

        <footer>Browser runtime verification is separate from native integration, performance profiling and Motion MCP access.</footer>
      </main>
    </MotionConfig>
  );
}

createRoot(document.getElementById('root')).render(<React.StrictMode><RuntimeLab /></React.StrictMode>);
