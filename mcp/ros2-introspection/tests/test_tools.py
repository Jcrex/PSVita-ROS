from ros2_introspection.backend import FakeBackend, TopicInfo, MessageSample


def test_list_topics_returns_known_topics():
    backend = FakeBackend(
        topics=[TopicInfo(name="/scan", types=["sensor_msgs/msg/LaserScan"])],
    )
    result = backend.list_topics()
    assert result == [TopicInfo(name="/scan", types=["sensor_msgs/msg/LaserScan"])]


def test_get_topic_type_returns_first_type():
    backend = FakeBackend(
        topics=[TopicInfo(name="/scan", types=["sensor_msgs/msg/LaserScan"])],
    )
    assert backend.get_topic_type("/scan") == "sensor_msgs/msg/LaserScan"


def test_get_topic_type_unknown_raises():
    backend = FakeBackend(topics=[])
    try:
        backend.get_topic_type("/nope")
        assert False, "expected KeyError"
    except KeyError:
        pass


def test_echo_topic_returns_sample():
    sample = MessageSample(topic="/scan", data={"ranges": [1.0, 2.0]})
    backend = FakeBackend(
        topics=[TopicInfo(name="/scan", types=["sensor_msgs/msg/LaserScan"])],
        samples={"/scan": sample},
    )
    assert backend.echo_topic("/scan") == sample
