import { CheckCircle2, Send } from "lucide-react";
import { useEffect, useState } from "react";
import type { FormEvent } from "react";

const subjectOptions = [
  { value: "technical-support", label: "Technical Support" },
  { value: "app-feedback", label: "App Feedback" },
  { value: "feature-request", label: "Feature Request" },
  { value: "business-inquiry", label: "Business Inquiry" },
  { value: "other", label: "Other" },
];

const initialForm = {
  name: "",
  email: "",
  subject: "",
  message: "",
};

export function ContactForm() {
  const [formData, setFormData] = useState(initialForm);
  const [isSubmitted, setIsSubmitted] = useState(false);

  useEffect(() => {
    if (!isSubmitted) {
      return undefined;
    }

    const timer = window.setTimeout(() => {
      setIsSubmitted(false);
      setFormData(initialForm);
    }, 4000);

    return () => window.clearTimeout(timer);
  }, [isSubmitted]);

  const handleSubmit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();

    const subjectLabel =
      subjectOptions.find((option) => option.value === formData.subject)?.label ??
      formData.subject;

    const emailSubject = encodeURIComponent(`LOGIT Contact: ${subjectLabel}`);
    const emailBody = encodeURIComponent(
      `Name: ${formData.name}
Email: ${formData.email}
Subject: ${subjectLabel}

Message:
${formData.message}`,
    );

    window.location.href = `mailto:logit.fitness@gmail.com?subject=${emailSubject}&body=${emailBody}`;
    setIsSubmitted(true);
  };

  const isDisabled =
    !formData.name || !formData.email || !formData.subject || !formData.message;

  if (isSubmitted) {
    return (
      <div className="contact-card contact-card--success">
        <span className="contact-card__icon">
          <CheckCircle2 size={24} />
        </span>
        <h3>Email draft ready</h3>
        <p>
          Your mail app should open with the message prefilled. If it does not,
          send a note directly to `logit.fitness@gmail.com`.
        </p>
      </div>
    );
  }

  return (
    <form className="contact-card contact-form" onSubmit={handleSubmit}>
      <div className="contact-card__header">
        <h3>Send a message</h3>
        <p>Use the form below to generate a prefilled email to the LOGIT team.</p>
      </div>

      <div className="form-grid">
        <label className="field">
          <span>Name</span>
          <input
            className="field__input"
            type="text"
            name="name"
            autoComplete="name"
            value={formData.name}
            onChange={(event) =>
              setFormData((current) => ({ ...current, name: event.target.value }))
            }
            placeholder="Your full name"
            required
          />
        </label>

        <label className="field">
          <span>Email</span>
          <input
            className="field__input"
            type="email"
            name="email"
            autoComplete="email"
            value={formData.email}
            onChange={(event) =>
              setFormData((current) => ({ ...current, email: event.target.value }))
            }
            placeholder="you@example.com"
            required
          />
        </label>
      </div>

      <label className="field">
        <span>Subject</span>
        <select
          className="field__input"
          name="subject"
          value={formData.subject}
          onChange={(event) =>
            setFormData((current) => ({ ...current, subject: event.target.value }))
          }
          required
        >
          <option value="" disabled>
            Select a subject
          </option>
          {subjectOptions.map((option) => (
            <option key={option.value} value={option.value}>
              {option.label}
            </option>
          ))}
        </select>
      </label>

      <label className="field">
        <span>Message</span>
        <textarea
          className="field__input field__input--textarea"
          name="message"
          value={formData.message}
          onChange={(event) =>
            setFormData((current) => ({ ...current, message: event.target.value }))
          }
          placeholder="Tell us what you need."
          required
        />
      </label>

      <button className="button button--primary contact-form__submit" type="submit" disabled={isDisabled}>
        <Send size={16} />
        <span>Open email draft</span>
      </button>
    </form>
  );
}
