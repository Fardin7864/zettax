import Predictions from "../predictions";
export default async function Page({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  return <Predictions initialId={(await params).id} />;
}
