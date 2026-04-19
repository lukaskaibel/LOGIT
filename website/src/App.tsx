import {
  ArrowUpRight,
  CheckCircle2,
  Download,
  Mail,
  ShieldCheck,
} from "lucide-react";
import { ContactForm } from "./components/ContactForm";
import appStoreButton from "./assets/8fe7cfbd7bc7f2e23a4ac0c9482266cb2b5027f8.png";

const appStoreUrl =
  "https://apps.apple.com/us/app/logit-track-your-workouts/id6444813640";
const screenshotBase = `${import.meta.env.BASE_URL}screenshots/en-US`;

const screenshots = {
  home: `${screenshotBase}/iPhone 17 Pro Max-01_Home_framed.png`,
  muscleGroups: `${screenshotBase}/iPhone 17 Pro Max-02_MuscleGroupBack_framed.png`,
  exerciseDetail: `${screenshotBase}/iPhone 17 Pro Max-03_ExerciseDetail_framed.png`,
  workoutDetail: `${screenshotBase}/iPhone 17 Pro Max-04_WorkoutDetail_framed.png`,
  workoutRecorder: `${screenshotBase}/iPhone 17 Pro Max-05_WorkoutRecorder_framed.png`,
  superDropSet: `${screenshotBase}/iPhone 17 Pro Max-06_SuperDropSet_framed.png`,
  liveActivity: `${screenshotBase}/iPhone 17 Pro Max-07_LiveActivity_framed.png`,
  bodyFat: `${screenshotBase}/iPhone 17 Pro Max-08_BodyFat_framed.png`,
};

const showcaseCards = [
  {
    keyword: "TRAIN",
    title: "Your training at a glance.",
    body: "Weekly goals, overall sets, volume, and muscle focus stay visible the second you open the app.",
    image: screenshots.home,
    alt: "LOGIT summary screen framed for the App Store",
  },
  {
    keyword: "RECORD",
    title: "Log sets fast, stay in the zone.",
    body: "Start a session, move through sets quickly, and keep the workout flow uninterrupted.",
    image: screenshots.workoutRecorder,
    alt: "LOGIT workout recorder screen framed for the App Store",
  },
  {
    keyword: "BALANCE",
    title: "Balance every muscle group.",
    body: "See where the week is concentrated before your programming drifts out of shape.",
    image: screenshots.muscleGroups,
    alt: "LOGIT muscle group balance screen framed for the App Store",
  },
  {
    keyword: "PROGRESS",
    title: "Watch your body transform.",
    body: "Track measurements and training momentum without leaving the same calm interface.",
    image: screenshots.bodyFat,
    alt: "LOGIT body measurement screen framed for the App Store",
  },
];

const detailPoints = [
  "Custom exercise library with reusable workout templates.",
  "Per-exercise progress tracking for weight, reps, volume, and set count.",
  "Supersets and dropsets built into the logging flow.",
  "Live Activity support to keep the current workout on the Lock Screen.",
];

const proFeatures = [
  "Charts for weight, reps, volume, and sets over time.",
  "Measurements for body weight, calories, and other metrics.",
  "Scan a Workout to turn a photo into a workout template.",
];

function AppStoreBadge({ className = "" }: { className?: string }) {
  return (
    <a
      className={`app-store-badge ${className}`.trim()}
      href={appStoreUrl}
      target="_blank"
      rel="noreferrer"
      aria-label="Download LOGIT on the App Store"
    >
      <img src={appStoreButton} alt="Download on the App Store" />
    </a>
  );
}

function App() {
  return (
    <div className="site-shell">
      <header className="topbar">
        <div className="topbar__inner">
          <a className="brand" href="#top" aria-label="LOGIT home">
            <span className="brand__dot" />
            <span>LOGIT.</span>
          </a>

          <nav className="topbar__nav" aria-label="Primary">
            <a href="#story">Story</a>
            <a href="#depth">Depth</a>
            <a href="#pro">Pro</a>
            <a href="#contact">Contact</a>
          </nav>

          <a className="topbar__link" href={appStoreUrl} target="_blank" rel="noreferrer">
            App Store
          </a>
        </div>
      </header>

      <main id="top">
        <section className="hero">
          <div className="hero__copy reveal-up">
            <p className="hero__label">Workout Tracker & Fitness Log</p>
            <span className="hero__keyword">TRAIN</span>
            <h1>Train with a plan. Log workouts fast. See real progress.</h1>
            <p className="hero__lead">
              LOGIT brings the App Store presentation onto the web: black surfaces,
              bright lime accents, and framed screens that show the product exactly
              as it feels on iPhone.
            </p>

            <div className="hero__actions">
              <AppStoreBadge />
              <a className="button button--secondary" href="#story">
                <span>See the screens</span>
                <ArrowUpRight size={16} />
              </a>
            </div>
          </div>

          <div className="hero__stage reveal-up" style={{ animationDelay: "140ms" }}>
            <div className="hero__glow hero__glow--lime" />
            <div className="hero__glow hero__glow--blue" />
            <img
              className="hero__poster"
              src={screenshots.home}
              alt="LOGIT App Store hero screenshot"
            />
            <div className="hero__aside">
              <p>TRAIN</p>
              <strong>Your training at a glance.</strong>
              <span>Weekly goals, volume, sets, and balance in one view.</span>
            </div>
          </div>
        </section>

        <section className="story" id="story">
          <div className="section-heading reveal-up">
            <p className="section-heading__eyebrow">App Store Story</p>
            <h2>The website now speaks in the same visual language as the listing.</h2>
            <p>
              Each screen carries one message, one screenshot, and one reason to
              keep scrolling.
            </p>
          </div>

          <div className="story-grid">
            {showcaseCards.map((card, index) => (
              <article
                key={card.keyword}
                className="story-card reveal-up"
                style={{ animationDelay: `${80 + index * 90}ms` }}
              >
                <div className="story-card__copy">
                  <span className="story-card__keyword">{card.keyword}</span>
                  <h3>{card.title}</h3>
                  <p>{card.body}</p>
                </div>
                <img src={card.image} alt={card.alt} />
              </article>
            ))}
          </div>
        </section>

        <section className="depth" id="depth">
          <div className="depth__rail">
            <div className="depth__copy reveal-up">
              <p className="section-heading__eyebrow">Product Depth</p>
              <h2>Built for disciplined sessions, not generic fitness noise.</h2>
              <p>
                LOGIT keeps the interface dense but readable. The same design rules
                that shape the app now shape the website.
              </p>

              <ul className="detail-list">
                {detailPoints.map((point) => (
                  <li key={point}>
                    <CheckCircle2 size={18} />
                    <span>{point}</span>
                  </li>
                ))}
              </ul>
            </div>

            <div className="depth__visual reveal-up" style={{ animationDelay: "120ms" }}>
              <div className="poster-stack">
                <figure className="poster-stack__primary">
                  <img
                    src={screenshots.exerciseDetail}
                    alt="LOGIT personal bests exercise detail screenshot"
                  />
                  <figcaption>
                    <span>TRACK</span>
                    <strong>Know your personal bests.</strong>
                  </figcaption>
                </figure>

                <figure className="poster-stack__secondary">
                  <img
                    src={screenshots.liveActivity}
                    alt="LOGIT live activity lock screen screenshot"
                  />
                  <figcaption>
                    <span>LIVE</span>
                    <strong>Your workout on the Lock Screen.</strong>
                  </figcaption>
                </figure>
              </div>
            </div>
          </div>
        </section>

        <section className="pro" id="pro">
          <div className="pro__intro reveal-up">
            <p className="section-heading__eyebrow">LOGIT Pro</p>
            <h2>Premium tools, shown through the actual product.</h2>
            <p>
              Charts, measurements, and scanned workout templates extend the same
              fast logging workflow instead of creating a separate experience.
            </p>
          </div>

          <div className="pro__grid">
            <div className="pro__screens reveal-up" style={{ animationDelay: "100ms" }}>
              <img src={screenshots.bodyFat} alt="LOGIT body metrics screenshot" />
              <img src={screenshots.superDropSet} alt="LOGIT superset workout screenshot" />
            </div>

            <div className="pro__panel reveal-up" style={{ animationDelay: "180ms" }}>
              <span className="pro__kicker">Upgrade without changing pace</span>
              <ul className="pro-list">
                {proFeatures.map((feature) => (
                  <li key={feature}>{feature}</li>
                ))}
              </ul>
              <a className="button button--primary" href={appStoreUrl} target="_blank" rel="noreferrer">
                <Download size={16} />
                <span>View on the App Store</span>
              </a>
            </div>
          </div>
        </section>

        <section className="contact" id="contact">
          <div className="contact__copy reveal-up">
            <p className="section-heading__eyebrow">Contact</p>
            <h2>Questions, product feedback, or support requests.</h2>
            <p>
              Reach the LOGIT team directly or open the App Store listing for the
              latest release information.
            </p>

            <div className="contact-links">
              <a href="mailto:logit.fitness@gmail.com" className="contact-link">
                <Mail size={18} />
                <span>logit.fitness@gmail.com</span>
              </a>
              <a href={appStoreUrl} target="_blank" rel="noreferrer" className="contact-link">
                <Download size={18} />
                <span>App Store listing</span>
              </a>
              <a
                href="https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
                target="_blank"
                rel="noreferrer"
                className="contact-link"
              >
                <ShieldCheck size={18} />
                <span>Terms of Use (EULA)</span>
              </a>
            </div>
          </div>

          <div className="reveal-up" style={{ animationDelay: "120ms" }}>
            <ContactForm />
          </div>
        </section>
      </main>

      <footer className="footer">
        <div className="footer__inner">
          <div>
            <a className="brand" href="#top">
              <span className="brand__dot" />
              <span>LOGIT.</span>
            </a>
            <p className="footer__copy">
              Focused workout logging, clearer progress, and calmer training data.
            </p>
          </div>
          <AppStoreBadge className="footer__badge" />
        </div>
      </footer>
    </div>
  );
}

export default App;
