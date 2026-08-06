# syntax=docker/dockerfile:1
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY services/backend/Aumbrye.sln services/backend/
COPY services/backend/src/ services/backend/src/
COPY packages/ packages/
RUN dotnet restore services/backend/src/Aumbrye.Api/Aumbrye.Api.csproj
RUN dotnet publish services/backend/src/Aumbrye.Api/Aumbrye.Api.csproj \
    -c Release -o /app/publish --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app
RUN adduser --system --group --no-create-home aumbrye
COPY --from=build /app/publish .
COPY content/ /app/content/
ENV AUMBRYE_CONTENT_ROOT=/app/content \
    ASPNETCORE_URLS=http://+:8080 \
    ASPNETCORE_ENVIRONMENT=Production
EXPOSE 8080
USER aumbrye
HEALTHCHECK --interval=30s --timeout=3s --start-period=20s --retries=3 \
  CMD ["dotnet", "Aumbrye.Api.dll", "--healthcheck"]
ENTRYPOINT ["dotnet", "Aumbrye.Api.dll"]
