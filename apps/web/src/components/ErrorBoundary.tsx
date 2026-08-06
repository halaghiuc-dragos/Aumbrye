import { Component, type ErrorInfo, type ReactNode } from "react";

type Props = {
  children: ReactNode;
};

type State = {
  hasError: boolean;
};

export default class ErrorBoundary extends Component<Props, State> {
  state: State = { hasError: false };

  static getDerivedStateFromError(): State {
    return { hasError: true };
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    console.error("Unhandled render error", error, info);
  }

  private handleRetry = () => {
    this.setState({ hasError: false });
  };

  render() {
    if (this.state.hasError) {
      return (
        <section className="page">
          <h2>Something went wrong</h2>
          <p className="muted">The page hit an unexpected error. You can try again or reload.</p>
          <button type="button" onClick={this.handleRetry}>
            Try again
          </button>
        </section>
      );
    }

    return this.props.children;
  }
}
